-- Enhanced LazyVim Plugin Extractor with Two-Pass Processing
-- This uses a minimal LazyVim setup to get the plugin list and provides mapping suggestions

-- Load mapping suggestion engine
local suggest_mappings = require("suggest-mappings")

-- Load user plugin scanner
local user_scanner = require("scan-user-plugins")

-- Function to load existing plugins.json
local function load_existing_plugins(file_path)
	local existing_plugins = {}
	local file = io.open(file_path, "r")
	if not file then
		print(string.format("Note: No existing plugins.json found at %s, will create new one", file_path))
		return existing_plugins
	end

	local content = file:read("*all")
	file:close()

	-- Use vim.json to parse the JSON properly
	local ok, json_data = pcall(vim.json.decode, content)
	if not ok then
		print("Warning: Could not parse existing plugins.json")
		return existing_plugins
	end

	-- Extract plugins from parsed JSON
	if json_data and json_data.plugins then
		for _, plugin in ipairs(json_data.plugins) do
			if plugin.name then
				existing_plugins[plugin.name] = {
					name = plugin.name,
					version_info = plugin.version_info or {}
				}
			end
		end
	end

	local count = 0
	for _ in pairs(existing_plugins) do
		count = count + 1
	end
	print(string.format("Loaded %d existing plugins from %s", count, file_path))

	return existing_plugins
end

-- Function to parse plugin mappings from JSON
local function parse_plugin_mappings(mappings_file)
	local mappings = {}
	local multi_module_mappings = {}

	local file = io.open(mappings_file, "r")
	if not file then
		print("Warning: Could not open data/mappings.json, proceeding without existing mappings")
		return mappings, multi_module_mappings
	end

	local content = file:read("*all")
	file:close()

	-- Parse JSON content
	local success, parsed = pcall(function() return vim.fn.json_decode(content) end)
	if not success then
		print("Warning: Could not parse mappings JSON, proceeding without existing mappings")
		return mappings, multi_module_mappings
	end

	-- Separate standard mappings from multi-module mappings
	for plugin_name, mapping_data in pairs(parsed) do
		-- Skip the comment field
		if plugin_name ~= "_comment" then
			if type(mapping_data) == "string" then
				-- Standard mapping: "plugin/name": "nixpkgs-name"
				mappings[plugin_name] = mapping_data
			elseif type(mapping_data) == "table" and mapping_data.package and mapping_data.module then
				-- Multi-module mapping: "plugin/name": { "package": "pkg", "module": "mod" }
				multi_module_mappings[plugin_name] = {
					package = mapping_data.package,
					module = mapping_data.module
				}
			end
		end
	end

	local function count_table(t)
		local count = 0
		for _ in pairs(t) do
			count = count + 1
		end
		return count
	end

	print(
		string.format(
			"Loaded %d standard mappings and %d multi-module mappings",
			count_table(mappings),
			count_table(multi_module_mappings)
		)
	)

	return mappings, multi_module_mappings
end

function ExtractLazyVimPlugins(lazyvim_path, output_file, version, commit)
	-- Load existing plugins.json for comparison
	local existing_plugins_file = output_file:gsub("%.tmp$", "")
	local existing_plugins = load_existing_plugins(existing_plugins_file)

	-- Set up paths
	vim.opt.runtimepath:prepend(lazyvim_path)

	-- Mock LazyVim global that some plugin modules might expect
	---@diagnostic disable-next-line: missing-fields
	_G.LazyVim = {
		util = setmetatable({}, {
			__index = function() return function() end end
		})
	}

	-- Parse existing plugin mappings
	local mappings_file = "data/mappings.json"
	local existing_mappings, multi_module_mappings = parse_plugin_mappings(mappings_file)

	-- Load LazyVim's plugin specifications directly
	local plugins = {}
	local seen = {}
	local unmapped_plugins = {}
	local extraction_report = {
		total_plugins = 0,
		mapped_plugins = 0,
		unmapped_plugins = 0,
		multi_module_plugins = 0,
		mapping_suggestions = {},
	}

	-- Known mappings from short names to full names
	local short_to_full = {
		["mason.nvim"] = "mason-org/mason.nvim",
		["gitsigns.nvim"] = "lewis6991/gitsigns.nvim",
		["snacks.nvim"] = "folke/snacks.nvim",
	}

	-- Function to normalize plugin names
	local function normalize_name(name)
		if type(name) ~= "string" then
			return nil
		end

		-- If it's already in owner/repo format, return as-is
		if name:match("^[%w%-]+/[%w%-%._]+$") then
			return name
		end

		-- Check if it's a known short name
		return short_to_full[name]
	end

	-- Function to normalize dependencies
	local function normalize_deps(deps)
		if not deps then
			return {}
		end

		local normalized = {}
		if type(deps) == "string" then
			local norm = normalize_name(deps)
			if norm then
				table.insert(normalized, norm)
			end
		elseif type(deps) == "table" then
			for _, dep in ipairs(deps) do
				if type(dep) == "string" then
					local norm = normalize_name(dep) or dep
					table.insert(normalized, norm)
				elseif type(dep) == "table" and dep[1] then
					local norm = normalize_name(dep[1]) or dep[1]
					table.insert(normalized, norm)
				end
			end
		end
		return normalized
	end

	-- Helper function to execute shell commands and capture output
	local function execute_command(cmd)
		local handle = io.popen(cmd .. " 2>/dev/null")
		if not handle then
			return nil
		end
		local result = handle:read("*all")
		local success = handle:close()
		if success and result then
			return result:match("^%s*(.-)%s*$") -- trim whitespace
		end
		return nil
	end

	-- Get latest tag using git ls-remote (avoids GitHub API rate limits)
	local function get_latest_tag(owner, repo)
		if not owner or not repo then
			return nil
		end

		local cmd = string.format(
			"git ls-remote --tags https://github.com/%s/%s 2>/dev/null | " ..
			"sed 's/.*refs\\/tags\\///' | " ..
			"sed 's/\\^{}$//' | " ..  -- Strip ^{} from annotated tags
			"grep -E '^v?[0-9]+\\.[0-9]+' | " ..
			"sort -rV | " ..
			"head -1",
			owner, repo
		)

		return execute_command(cmd)
	end

	-- Fetch plugin version info using nix-prefetch-git
	local function fetch_plugin_version(owner, repo, ref)
		if not owner or not repo then
			return nil
		end

		local url = string.format("https://github.com/%s/%s", owner, repo)
		local cmd

		if ref then
			cmd = string.format("nix-prefetch-git --quiet --url '%s' --rev '%s'", url, ref)
		else
			cmd = string.format("nix-prefetch-git --quiet --url '%s'", url)
		end

		local result = execute_command(cmd)
		if result then
			-- Parse JSON output from nix-prefetch-git
			local rev = result:match('"rev":%s*"([^"]+)"')
			local sha256 = result:match('"sha256":%s*"([^"]+)"')

			if rev and sha256 then
				return {
					commit = rev,
					sha256 = sha256
				}
			end
		end

		return nil
	end

	-- Enrich plugin with version information
	local function enrich_plugin_version_info(plugin_info, existing_plugin_data)
		if not plugin_info.owner or not plugin_info.repo then
			return
		end

		print(string.format("    Fetching version info for %s...", plugin_info.name))

		-- Preserve LazyVim version info that was captured during extraction
		local lazyvim_version = plugin_info.version_info.lazyvim_version
		local lazyvim_version_type = plugin_info.version_info.lazyvim_version_type

		-- Determine source strategy based on LazyVim specifications
		local version_data
		if lazyvim_version_type == "branch" then
			-- LazyVim specified a branch - use it exactly
			print(string.format("      Using branch '%s' (LazyVim specification)", lazyvim_version))
			version_data = fetch_plugin_version(plugin_info.owner, plugin_info.repo, "refs/heads/" .. lazyvim_version)
			if version_data then
				plugin_info.version_info.tag = nil
				plugin_info.version_info.latest_tag = nil
				plugin_info.version_info.branch = lazyvim_version
			end
		elseif lazyvim_version == false or (lazyvim_version_type == "version" and lazyvim_version == false) then
			-- LazyVim specified version = false - use latest commit, no tags
			print("      Using latest commit (LazyVim: version = false)")
			version_data = fetch_plugin_version(plugin_info.owner, plugin_info.repo, nil)
			if version_data then
				plugin_info.version_info.tag = nil
				plugin_info.version_info.latest_tag = nil
			end
		elseif lazyvim_version_type == "commit" then
			-- LazyVim specified a specific commit
			print(string.format("      Using commit '%s' (LazyVim specification)", lazyvim_version))
			version_data = fetch_plugin_version(plugin_info.owner, plugin_info.repo, lazyvim_version)
			if version_data then
				plugin_info.version_info.tag = nil
				plugin_info.version_info.latest_tag = nil
			end
		elseif lazyvim_version_type == "tag" then
			-- LazyVim specified a specific tag
			print(string.format("      Using tag '%s' (LazyVim specification)", lazyvim_version))
			version_data = fetch_plugin_version(plugin_info.owner, plugin_info.repo, lazyvim_version)
			if version_data then
				plugin_info.version_info.tag = lazyvim_version
				plugin_info.version_info.latest_tag = lazyvim_version
			end
		else
			-- Try to get latest tag first
			local latest_tag = get_latest_tag(plugin_info.owner, plugin_info.repo)

			if latest_tag and latest_tag ~= "" then
				print(string.format("      Found tag: %s", latest_tag))
				version_data = fetch_plugin_version(plugin_info.owner, plugin_info.repo, latest_tag)
				if version_data then
					plugin_info.version_info.tag = latest_tag
					plugin_info.version_info.latest_tag = latest_tag
				end
			else
				print("      No tags found, fetching latest commit...")
				version_data = fetch_plugin_version(plugin_info.owner, plugin_info.repo, nil)
				if version_data then
					plugin_info.version_info.tag = nil
					plugin_info.version_info.latest_tag = nil
				end
			end
		end

		if version_data then
			-- Check if the version has actually changed
			local version_changed = false
			if existing_plugin_data and existing_plugin_data.version_info then
				local old_info = existing_plugin_data.version_info
				-- Compare the actual version identifiers
				if version_data.commit ~= old_info.commit then
					version_changed = true
					print(string.format("      Version changed: %s -> %s",
						old_info.commit and old_info.commit:sub(1, 8) or "none",
						version_data.commit:sub(1, 8)))
				elseif plugin_info.version_info.tag ~= old_info.tag then
					version_changed = true
					print(string.format("      Tag changed: %s -> %s",
						old_info.tag or "none",
						plugin_info.version_info.tag or "none"))
				elseif plugin_info.version_info.branch ~= old_info.branch then
					version_changed = true
					print(string.format("      Branch changed: %s -> %s",
						old_info.branch or "none",
						plugin_info.version_info.branch or "none"))
				end
			else
				-- No existing data, so it's a new plugin
				version_changed = true
				print("      New plugin")
			end

			plugin_info.version_info.commit = version_data.commit
			plugin_info.version_info.sha256 = version_data.sha256

			-- Only update fetched_at if the version actually changed
			if version_changed then
				plugin_info.version_info.fetched_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
				print(string.format("      ✓ Got commit: %s (updated)", version_data.commit:sub(1, 8)))
			else
				-- Preserve the existing fetched_at timestamp
				if existing_plugin_data and existing_plugin_data.version_info and existing_plugin_data.version_info.fetched_at then
					plugin_info.version_info.fetched_at = existing_plugin_data.version_info.fetched_at
				else
					-- Fallback: set new fetched_at if we don't have an existing one
					plugin_info.version_info.fetched_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
				end
				print(string.format("      ✓ Got commit: %s (unchanged)", version_data.commit:sub(1, 8)))
			end
		else
			print("      ⚠ Could not fetch version info")
		end

		-- Always restore LazyVim version specification information
		plugin_info.version_info.lazyvim_version = lazyvim_version
		plugin_info.version_info.lazyvim_version_type = lazyvim_version_type

		-- Add small delay to be respectful to git servers
		os.execute("sleep 0.2")
	end

	-- Function to check if a plugin is mapped (manual or automatic)
	local function is_plugin_mapped(plugin_name)
		-- Check if it's in existing mappings or multi-module mappings
		if existing_mappings[plugin_name] ~= nil or multi_module_mappings[plugin_name] ~= nil then
			return true
		end

		-- Test automatic resolution patterns (same logic as module.nix)
		local owner, repo_name = plugin_name:match("^([^/]+)/(.+)$")
		if not repo_name then
			return false
		end

		local nixpkgs_name = nil

		-- Pattern 1: owner/name.nvim -> name-nvim (most common)
		if repo_name:match("%.nvim$") then
			local base_name = repo_name:gsub("%.nvim$", "")
			nixpkgs_name = base_name .. "-nvim"
		-- Pattern 2: owner/name-nvim -> name-nvim
		elseif repo_name:match("%-nvim$") then
			nixpkgs_name = repo_name
		-- Pattern 3: owner/nvim-name -> nvim-name
		elseif repo_name:match("^nvim%-") then
			nixpkgs_name = repo_name
		-- Pattern 4: owner/name -> name (convert dashes to underscores)
		else
			nixpkgs_name = repo_name:gsub("%-", "_"):gsub("%.", "_")
		end

		-- Test if the resolved name exists in nixpkgs (use nixos-unstable)
		if nixpkgs_name then
			local cmd = string.format(
				"nix eval --impure --expr 'let pkgs = import (fetchTarball \"https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz\") {}; in pkgs.vimPlugins.%s or null' 2>&1",
				nixpkgs_name
			)
			print(string.format("DEBUG: Checking %s -> %s", plugin_name, nixpkgs_name))
			print(string.format("DEBUG: Command: %s", cmd))

			local handle = io.popen(cmd)
			if handle then
				local result = handle:read("*all")
				local success = handle:close()
				print(string.format("DEBUG: Result: %s", result:gsub("\n", "\\n")))
				print(string.format("DEBUG: Success: %s", tostring(success)))

				-- Check if the result is not null (package exists)
				if success and result and not result:match("null") and result:match("«derivation") then
					print(string.format("DEBUG: ✓ Found %s -> %s", plugin_name, nixpkgs_name))
					return true
				else
					print(string.format("DEBUG: ✗ Not found %s -> %s", plugin_name, nixpkgs_name))
				end
			else
				print(string.format("DEBUG: Failed to execute command for %s", plugin_name))
			end
		end

		return false
	end

	-- Function to collect plugin specs recursively
	local function collect_plugin(spec, is_core_plugin, source_module)
		if type(spec) == "string" then
			local normalized = normalize_name(spec)
			-- Only add if it's in owner/repo format
			if normalized and not seen[normalized] then
				seen[normalized] = true

				-- Extract repository info
				local owner, repo = normalized:match("^([^/]+)/(.+)$")

				local plugin_info = {
					name = normalized,
					owner = owner,
					repo = repo,
					dependencies = {},
					source_file = source_module or "string_spec",
					is_core = is_core_plugin or false,
					-- Enhanced version info structure
					version_info = {
						-- LazyVim specification (none for string specs)
						lazyvim_version = nil,
						lazyvim_version_type = nil,
						-- Resolved version (filled by fetch script)
						commit = nil,
						branch = nil,
						tag = nil,
						-- Build metadata
						nixpkgs_version = nil,
						sha256 = nil,
						fetched_at = nil,
					},
				}

				-- Add multi-module info if applicable
				if multi_module_mappings[normalized] then
					plugin_info.multiModule = {
						basePackage = multi_module_mappings[normalized].package,
						module = multi_module_mappings[normalized].module,
						repository = normalized:match("^(.+)/")
							.. "/"
							.. multi_module_mappings[normalized].package:gsub("%-nvim$", ".nvim"),
					}
					extraction_report.multi_module_plugins = extraction_report.multi_module_plugins + 1
				end

				-- Track mapping status
				if is_plugin_mapped(normalized) then
					extraction_report.mapped_plugins = extraction_report.mapped_plugins + 1
				else
					extraction_report.unmapped_plugins = extraction_report.unmapped_plugins + 1
					table.insert(unmapped_plugins, normalized)
				end

				table.insert(plugins, plugin_info)
			end
		elseif type(spec) == "table" then
			-- Handle table spec
			local name = spec[1] or spec.name
			if name and type(name) == "string" then
				local normalized = normalize_name(name)

				-- Only process if it's in owner/repo format
				if normalized and not seen[normalized] then
					seen[normalized] = true

					-- Normalize dependencies
					local deps = normalize_deps(spec.dependencies)

					-- Extract repository info
					local owner, repo = normalized:match("^([^/]+)/(.+)$")

					-- Check if plugin has mapping
					local plugin_info = {
						name = normalized,
						owner = owner,
						repo = repo,
						dependencies = deps,
						event = spec.event,
						cmd = spec.cmd,
						ft = spec.ft,
						enabled = spec.enabled,
						lazy = spec.lazy,
						priority = spec.priority,
						source_file = source_module or "table_spec",
						is_core = is_core_plugin or false,
						-- Enhanced version info structure
						version_info = {
							-- LazyVim specification
							lazyvim_version = spec.branch and spec.branch
								or (spec.version ~= nil and spec.version)
								or spec.tag or spec.commit
								or nil,
							lazyvim_version_type = spec.branch and "branch"
								or (spec.version ~= nil and "version")
								or (spec.tag and "tag")
								or (spec.commit and "commit")
								or nil,
							-- Resolved version (filled by fetch script)
							commit = nil,
							branch = nil,
							tag = nil,
							-- Build metadata
							nixpkgs_version = nil,  -- Nixpkgs version for comparison (filled at build time)
							sha256 = nil,
							fetched_at = nil,
						},
					}

					-- Add multi-module info if applicable
					if multi_module_mappings[normalized] then
						plugin_info.multiModule = {
							basePackage = multi_module_mappings[normalized].package,
							module = multi_module_mappings[normalized].module,
							repository = normalized:match("^(.+)/")
								.. "/"
								.. multi_module_mappings[normalized].package:gsub("%-nvim$", ".nvim"),
						}
						extraction_report.multi_module_plugins = extraction_report.multi_module_plugins + 1
					end

					-- Track mapping status
					if is_plugin_mapped(normalized) then
						extraction_report.mapped_plugins = extraction_report.mapped_plugins + 1
					else
						extraction_report.unmapped_plugins = extraction_report.unmapped_plugins + 1
						table.insert(unmapped_plugins, normalized)
					end

					-- Fetch version information
					enrich_plugin_version_info(plugin_info, existing_plugins[normalized])

					table.insert(plugins, plugin_info)
				end
			end

			-- Recursively process nested specs
			for _, v in ipairs(spec) do
				if type(v) == "table" or type(v) == "string" then
					collect_plugin(v, is_core_plugin, source_module)
				end
			end

			-- Process dependencies
			if spec.dependencies then
				if type(spec.dependencies) == "table" then
					for _, dep in ipairs(spec.dependencies) do
						collect_plugin(dep, is_core_plugin, source_module)
					end
				end
			end
		end
	end

	-- Function to extract plugins from a single LazyVim extra file
	local function extract_plugins_from_extra(extra_path, relative_path)
		-- Read the extra file
		local file = io.open(extra_path, "r")
		if not file then
			return {}
		end
		local content = file:read("*all")
		file:close()

		-- Create a safe environment for loading the extra
		local env = {
			-- Common Lua functions that extras might use
			pairs = pairs,
			ipairs = ipairs,
			tonumber = tonumber,
			tostring = tostring,
			type = type,
			table = table,
			string = string,
			math = math,
			-- Mock LazyVim functions that some extras might reference
			LazyVim = {
				has = function() return false end,
				on_very_lazy = function() end,
			},
			vim = {
				fn = {},
				cmd = function() end,
			},
		}

		-- Load the extra file
		local chunk, err = load(content, extra_path, "t", env)
		if not chunk then
			print("Warning: Failed to parse extra " .. relative_path .. ": " .. err)
			return {}
		end

		-- Execute and get the result
		local success, result = pcall(chunk)
		if not success then
			print("Warning: Failed to execute extra " .. relative_path .. ": " .. result)
			return {}
		end

		-- The extra should return a table
		if type(result) ~= "table" then
			return {}
		end

		local plugins = {}

		-- Extract plugin specs from the result
		-- Extras return an array-like table where each entry is either:
		-- 1. A plugin spec table with a plugin name as [1]
		-- 2. Metadata like "recommended"
		for _, item in ipairs(result) do
			if type(item) == "table" and item[1] and type(item[1]) == "string" then
				-- This is a plugin spec
				local plugin_name = item[1]

				-- Normalize the plugin name
				local normalized = normalize_name(plugin_name)
				if normalized and not seen[normalized] then
					seen[normalized] = true

					-- Extract owner/repo from the plugin name
					local owner, repo = normalized:match("^([^/]+)/(.+)$")
					if owner and repo then
						-- Convert relative path to source_file format
						-- e.g., "ai/copilot.lua" -> "extras.ai.copilot"
						local source_file = "extras." .. relative_path:gsub("/", "."):gsub("%.lua$", "")

						local plugin_info = {
							name = normalized,
							owner = owner,
							repo = repo,
							dependencies = normalize_deps(item.dependencies),
							event = item.event,
							cmd = item.cmd,
							ft = item.ft,
							enabled = item.enabled,
							lazy = item.lazy,
							priority = item.priority,
							source_file = source_file,
							is_core = false,  -- Extras are never core
							-- Enhanced version info structure
							version_info = {
								-- LazyVim specification
								lazyvim_version = item.version ~= nil and item.version
									or item.tag or item.commit or item.branch,
								lazyvim_version_type = item.version ~= nil and "version"
									or item.tag and "tag"
									or item.commit and "commit"
									or item.branch and "branch"
									or nil,
								-- Resolved version (filled by fetch script)
								commit = nil,
								branch = nil,
								tag = nil,
								-- Build metadata
								nixpkgs_version = nil,
								sha256 = nil,
								fetched_at = nil,
							},
						}

						-- Add multi-module info if applicable
						if multi_module_mappings[normalized] then
							plugin_info.multiModule = {
								basePackage = multi_module_mappings[normalized].package,
								module = multi_module_mappings[normalized].module,
								repository = normalized:match("^(.+)/")
									.. "/"
									.. multi_module_mappings[normalized].package:gsub("%-nvim$", ".nvim"),
							}
							extraction_report.multi_module_plugins = extraction_report.multi_module_plugins + 1
						end

						-- Track mapping status
						if is_plugin_mapped(normalized) then
							extraction_report.mapped_plugins = extraction_report.mapped_plugins + 1
						else
							extraction_report.unmapped_plugins = extraction_report.unmapped_plugins + 1
							table.insert(unmapped_plugins, normalized)
						end

						-- Fetch version information
						enrich_plugin_version_info(plugin_info, existing_plugins[normalized])

						table.insert(plugins, plugin_info)
					end
				end
			end
		end

		return plugins
	end

	-- Function to scan LazyVim extras directory recursively
	local function scan_lazyvim_extras(lazyvim_path)
		local extras_path = lazyvim_path .. "/lua/lazyvim/plugins/extras"
		local extras_plugins = {}

		-- Helper function to scan directory recursively
		local function scan_directory(dir_path, relative_base)
			local handle = io.popen("find '" .. dir_path .. "' -name '*.lua' -type f 2>/dev/null")
			if not handle then
				print("Warning: Could not scan extras directory: " .. dir_path)
				return
			end

			for line in handle:lines() do
				-- Get relative path from extras directory
				local relative_path = line:sub(#extras_path + 2) -- +2 to remove leading slash
				if relative_path and relative_path ~= "" then
					print("  Processing extra: " .. relative_path)
					local plugins = extract_plugins_from_extra(line, relative_path)
					for _, plugin in ipairs(plugins) do
						table.insert(extras_plugins, plugin)
					end
				end
			end
			handle:close()
		end

		print("=== Scanning LazyVim extras ===")
		scan_directory(extras_path, "")
		print(string.format("Found %d plugins from extras", #extras_plugins))

		return extras_plugins
	end

	-- Load core LazyVim plugins (matching LazyVim's init.lua)
	local core_specs = {
		{ "folke/lazy.nvim", version = "*" },
		{ "LazyVim/LazyVim", priority = 10000, lazy = false, version = "*" },
		{ "folke/snacks.nvim", priority = 1000, lazy = false },
	}

	for _, spec in ipairs(core_specs) do
		collect_plugin(spec, true, "core.init")
	end

	-- Try to load LazyVim plugin modules
	local plugin_modules = {
		"coding",
		"colorscheme",
		"editor",
		"formatting",
		"linting",
		"lsp",
		"treesitter",
		"ui",
		"util",
	}

	for _, module in ipairs(plugin_modules) do
		local ok, module_specs = pcall(function()
			package.loaded["lazyvim.plugins." .. module] = nil
			return require("lazyvim.plugins." .. module)
		end)

		if ok and type(module_specs) == "table" then
			for _, spec in ipairs(module_specs) do
				collect_plugin(spec, true, "core." .. module)
			end
		end
	end

	-- Scan LazyVim extras and add them to plugins list
	local extras_plugins = scan_lazyvim_extras(lazyvim_path)
	for _, plugin in ipairs(extras_plugins) do
		table.insert(plugins, plugin)
	end


	-- Scan for user plugins and merge them with core plugins
	print("=== Scanning for user plugins ===")
	local user_plugins = user_scanner.scan_user_plugins()

	if #user_plugins > 0 then
		print(string.format("Found %d user plugins, merging with core plugins", #user_plugins))

		-- Process user plugins through the same logic as core plugins
		for _, user_plugin in ipairs(user_plugins) do
			if not seen[user_plugin.name] then
				seen[user_plugin.name] = true

				-- Mark as user plugin and track mapping status
				user_plugin.user_plugin = true
				user_plugin.source_file = "user_config"

				if is_plugin_mapped(user_plugin.name) then
					extraction_report.mapped_plugins = extraction_report.mapped_plugins + 1
				else
					extraction_report.unmapped_plugins = extraction_report.unmapped_plugins + 1
					table.insert(unmapped_plugins, user_plugin.name)
				end

				-- Fetch version information
				enrich_plugin_version_info(user_plugin, existing_plugins[user_plugin.name])

				table.insert(plugins, user_plugin)
			else
				print(string.format("Skipping user plugin %s (already exists in core)", user_plugin.name))
			end
		end
	else
		print("No user plugins found")
	end

	-- Sort and assign load order
	table.sort(plugins, function(a, b)
		return a.name < b.name
	end)

	for i, plugin in ipairs(plugins) do
		plugin.loadOrder = i
	end

	-- Finalize extraction report
	extraction_report.total_plugins = #plugins

	-- Generate mapping suggestions for unmapped plugins
	if #unmapped_plugins > 0 then
		-- Check if verification is requested via environment variable
		local verify_packages = os.getenv("VERIFY_NIXPKGS_PACKAGES") == "1"

		local analysis = suggest_mappings.analyze_unmapped_plugins(unmapped_plugins, verify_packages)
		extraction_report.mapping_suggestions = suggest_mappings.generate_mapping_updates(analysis)

		-- Write mapping analysis report
		local report_content = suggest_mappings.format_report(analysis)
		local report_file = io.open("data/mapping-analysis-report.md", "w")
		if report_file then
			report_file:write(report_content)
			report_file:close()
			print("Generated mapping analysis report: data/mapping-analysis-report.md")
		end
	end

	-- Create JSON output
	local json_data = {
		version = version,
		commit = commit,
		generated = os.date("%Y-%m-%d %H:%M:%S"),
		extraction_report = extraction_report,
		plugins = plugins,
	}

	-- JSON serialization
	local function to_json(data, indent)
		indent = indent or 0
		local spaces = string.rep("  ", indent)

		if type(data) == "table" then
			if #data > 0 and not data.name then
				-- Array
				local result = "[\n"
				for i, v in ipairs(data) do
					result = result .. spaces .. "  " .. to_json(v, indent + 1)
					if i < #data then
						result = result .. ","
					end
					result = result .. "\n"
				end
				return result .. spaces .. "]"
			else
				-- Object
				local result = "{\n"
				local first = true
				local ordered_keys = {
					"version",
					"commit",
					"generated",
					"extraction_report",
					"plugins",
					"name",
					"owner",
					"repo",
					"loadOrder",
					"dependencies",
					"multiModule",
					"source_file",
					"is_core",
					"event",
					"cmd",
					"ft",
					"enabled",
					"lazy",
					"priority",
					"version_info",
					"total_plugins",
					"mapped_plugins",
					"unmapped_plugins",
					"multi_module_plugins",
					"mapping_suggestions",
					"basePackage",
					"module",
					"repository",
					"lazyvim_version",
					"lazyvim_version_type",
					"nixpkgs_version",
					"branch",
					"tag",
					"sha256",
					"fetched_at",
				}

				for _, k in ipairs(ordered_keys) do
					local v = data[k]
					if v ~= nil then
						if not first then
							result = result .. ",\n"
						end
						first = false
						result = result .. spaces .. '  "' .. k .. '": ' .. to_json(v, indent + 1)
					end
				end

				if not first then
					result = result .. "\n"
				end
				return result .. spaces .. "}"
			end
		elseif type(data) == "string" then
			return '"' .. data:gsub('"', '\\"') .. '"'
		elseif type(data) == "boolean" then
			return tostring(data)
		elseif type(data) == "number" then
			return tostring(data)
		else
			return "null"
		end
	end

	-- Write output
	local file = io.open(output_file, "w")
	if file then
		file:write(to_json(json_data))
		file:close()

		-- Print extraction summary
		print("=== Plugin Extraction Summary ===")
		print(string.format("Total plugins extracted: %d", extraction_report.total_plugins))
		print(string.format("Mapped plugins: %d", extraction_report.mapped_plugins))
		print(string.format("Unmapped plugins: %d", extraction_report.unmapped_plugins))
		print(string.format("Multi-module plugins: %d", extraction_report.multi_module_plugins))

		if extraction_report.unmapped_plugins > 0 then
			print(string.format("Mapping suggestions generated: %d", #extraction_report.mapping_suggestions))
			print("Review data/mapping-analysis-report.md for details on unmapped plugins")
		end

		print("Successfully extracted " .. #plugins .. " plugins")
	else
		error("Failed to write output file")
	end
end
