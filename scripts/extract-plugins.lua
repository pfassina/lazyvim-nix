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

function ExtractLazyVimPlugins(lazyvim_path, output_file, version, commit, opts)
	opts = opts or {}
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
	local shared_extras_entries = opts.extras_entries

	-- Load LazyVim's plugin specifications directly
	local plugins = {}
	local seen = {}
	local repo_index = {}
	local extraction_report = {
		total_plugins = 0,
		mapped_plugins = 0,
		unmapped_plugins = 0,
		multi_module_plugins = 0,
		mapping_suggestions = {},
	}

	local prefetch_queue = {}
	local PREFETCH_CONCURRENCY = tonumber(os.getenv("LAZYVIM_PREFETCH_CONCURRENCY") or "6")
	if not PREFETCH_CONCURRENCY or PREFETCH_CONCURRENCY < 1 then
		PREFETCH_CONCURRENCY = 6
	end

	local REMOTE_CONCURRENCY = tonumber(os.getenv("LAZYVIM_REMOTE_CONCURRENCY") or "6")
	if not REMOTE_CONCURRENCY or REMOTE_CONCURRENCY < 1 then
		REMOTE_CONCURRENCY = 6
	end

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

	local function format_ref(ref)
		if not ref or ref == "" then
			return "HEAD"
		end
		if #ref >= 12 and ref:match("^[0-9a-f]+$") then
			return ref:sub(1, 8)
		end
		return ref
	end

	local function enqueue_prefetch(plugin_info, target, existing_info)
		local url = string.format("https://github.com/%s/%s", plugin_info.owner, plugin_info.repo)
		local args = { "--quiet", "--url", url }
		if target.prefetch_rev then
			table.insert(args, "--rev")
			table.insert(args, target.prefetch_rev)
		end

		print(string.format("      Queuing nix-prefetch-git (%s)", format_ref(target.prefetch_rev)))

		table.insert(prefetch_queue, {
			plugin = plugin_info,
			args = args,
			target = target,
			existing = existing_info,
		})
	end

	local function process_prefetch_queue()
		if #prefetch_queue == 0 then
			return
		end

		print(string.format("=== Prefetching %d plugins (concurrency %d) ===", #prefetch_queue, PREFETCH_CONCURRENCY))

		local loop = vim.loop
		local results = {}
		local active = 0
		local next_index = 1
		local completed = false

		local function start_next()
			if next_index > #prefetch_queue then
				if active == 0 then
					completed = true
				end
				return
			end

			local task = prefetch_queue[next_index]
			next_index = next_index + 1
			active = active + 1

			local stdout_pipe = loop.new_pipe(false)
			local stderr_pipe = loop.new_pipe(false)
			local output_chunks = {}
			local error_chunks = {}
			local handle

			local function finalize(code)
				stdout_pipe:close()
				stderr_pipe:close()
				if handle and not handle:is_closing() then
					handle:close()
				end

				active = active - 1
				table.insert(results, {
					task = task,
					code = code,
					stdout = table.concat(output_chunks),
					stderr = table.concat(error_chunks),
				})

				start_next()
				if next_index > #prefetch_queue and active == 0 then
					completed = true
				end
			end

			handle = loop.spawn("nix-prefetch-git", {
				args = task.args,
				stdio = { nil, stdout_pipe, stderr_pipe },
			}, finalize)

			if not handle then
				table.insert(results, {
					task = task,
					code = -1,
					stdout = "",
					stderr = "failed to spawn nix-prefetch-git",
				})
				active = active - 1
				start_next()
				if next_index > #prefetch_queue and active == 0 then
					completed = true
				end
				return
			end

			loop.read_start(stdout_pipe, function(err, data)
				if err then
					table.insert(error_chunks, err)
				elseif data then
					table.insert(output_chunks, data)
				end
			end)

			loop.read_start(stderr_pipe, function(err, data)
				if err then
					table.insert(error_chunks, err)
				elseif data then
					table.insert(error_chunks, data)
				end
			end)
		end

		for _ = 1, math.min(PREFETCH_CONCURRENCY, #prefetch_queue) do
			start_next()
		end

		vim.wait(1e8, function()
			return completed
		end, 50)

		for _, result in ipairs(results) do
			local task = result.task
			local plugin = task.plugin
			local target = task.target
			local existing = task.existing
			local version_info = plugin.version_info

			if result.code ~= 0 then
				error(string.format("nix-prefetch-git failed for %s: %s", plugin.name, result.stderr))
			end

			local ok, data = pcall(vim.json.decode, result.stdout)
			if not ok or not data or not data.rev or not data.sha256 then
				error(string.format("Invalid nix-prefetch-git output for %s", plugin.name))
			end

			local commit = data.rev
			local sha256 = data.sha256
			local version_changed = not (existing and existing.commit == commit)

			version_info.commit = commit
			version_info.sha256 = sha256

			if version_changed or not (existing and existing.fetched_at) then
				version_info.fetched_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
			else
				version_info.fetched_at = existing.fetched_at
			end

			if target.tag then
				version_info.tag = target.tag
				version_info.latest_tag = target.latest_tag or target.tag
				version_info.branch = nil
			elseif target.branch then
				version_info.branch = target.branch
				version_info.tag = nil
				version_info.latest_tag = target.latest_tag
			else
				version_info.tag = nil
				version_info.branch = nil
				version_info.latest_tag = target.latest_tag
			end

			if version_changed then
				print(string.format("      ✓ %s updated to %s", plugin.name, format_ref(commit)))
			else
				print(string.format("      ✓ %s verified at %s (unchanged)", plugin.name, format_ref(commit)))
			end
		end
	end

	local function parse_ls_remote(output)
		local data = {
			head = nil,
			heads = {},
			tags = {},
		}

		for line in output:gmatch("[^\n]+") do
			local commit, ref = line:match("^(%x+)%s+(.+)$")
			if commit and ref then
				if ref == "HEAD" then
					data.head = commit
				elseif ref:match("^refs/heads/") then
					local name = ref:match("^refs/heads/(.+)$")
					data.heads[name] = commit
				elseif ref:match("^refs/tags/") then
					local tag_name = ref:match("^refs/tags/(.+)$")
					local stripped = tag_name:gsub("%^{}$", "")
					if ref:sub(-3) == "^{}" then
						data.tags[stripped] = commit
					elseif not data.tags[stripped] then
						data.tags[stripped] = commit
					end
				end
			end
		end

		if not data.head then
			data.head = data.heads["main"] or data.heads["master"]
		end

		return data
	end

	local function fetch_remote_refs(index)
		local repos = {}
		for key, meta in pairs(index) do
			table.insert(repos, { key = key, url = meta.url })
		end

		if #repos == 0 then
			return {}
		end

		print(string.format("=== Resolving remote metadata for %d repositories (concurrency %d) ===", #repos, REMOTE_CONCURRENCY))

		local loop = vim.loop
		local active = 0
		local next_index = 1
		local completed = false
		local results = {}
		local errors = {}

		local function start_next()
			if next_index > #repos then
				if active == 0 then
					completed = true
				end
				return
			end

			local task = repos[next_index]
			next_index = next_index + 1
			active = active + 1

			local stdout_pipe = loop.new_pipe(false)
			local stderr_pipe = loop.new_pipe(false)
			local stdout_chunks = {}
			local stderr_chunks = {}
			local handle

			local function finalize(code)
				stdout_pipe:close()
				stderr_pipe:close()
				if handle and not handle:is_closing() then
					handle:close()
				end

				active = active - 1
				if code == 0 then
					results[task.key] = parse_ls_remote(table.concat(stdout_chunks))
				else
					table.insert(errors, {
						key = task.key,
						stderr = table.concat(stderr_chunks),
					})
				end

				start_next()
				if next_index > #repos and active == 0 then
					completed = true
				end
			end

			handle = loop.spawn("git", {
				args = { "ls-remote", task.url, "HEAD", "refs/heads/*", "refs/tags/*" },
				stdio = { nil, stdout_pipe, stderr_pipe },
			}, finalize)

			if not handle then
				table.insert(errors, { key = task.key, stderr = "failed to spawn git" })
				active = active - 1
				start_next()
				if next_index > #repos and active == 0 then
					completed = true
				end
				return
			end

			loop.read_start(stdout_pipe, function(err, data)
				if err then
					table.insert(stderr_chunks, err)
				elseif data then
					table.insert(stdout_chunks, data)
				end
			end)

			loop.read_start(stderr_pipe, function(err, data)
				if err then
					table.insert(stderr_chunks, err)
				elseif data then
					table.insert(stderr_chunks, data)
				end
			end)
		end

		for _ = 1, math.min(REMOTE_CONCURRENCY, #repos) do
			start_next()
		end

		vim.wait(1e8, function()
			return completed
		end, 50)

		if #errors > 0 then
			local lines = {}
			for _, err in ipairs(errors) do
				table.insert(lines, string.format("%s: %s", err.key, err.stderr))
			end
			error("Failed to fetch remote refs:\n" .. table.concat(lines, "\n"))
		end

		return results
	end

	local function select_latest_tag(tags)
		local best_tag
		local best_version
		for tag in pairs(tags) do
			local cleaned = tag:gsub("^v", "")
			local ok, parsed = pcall(vim.version.parse, cleaned)
			if ok and parsed then
				if not best_version or vim.version.cmp(parsed, best_version) > 0 then
					best_version = parsed
					best_tag = tag
				end
			end
		end
		if best_tag then
			return best_tag, tags[best_tag]
		end
		return nil, nil
	end

	local function determine_target(plugin_info, remote_info)
		local version_info = plugin_info.version_info
		local target = {
			lazyvim_version = version_info.lazyvim_version,
			lazyvim_version_type = version_info.lazyvim_version_type,
			mode = nil,
			branch = nil,
			tag = nil,
			latest_tag = nil,
			commit = nil,
			prefetch_rev = nil,
		}

		if version_info.lazyvim_version_type == "branch" and version_info.lazyvim_version then
			target.mode = "branch"
			target.branch = version_info.lazyvim_version
			target.commit = remote_info.heads[target.branch] or remote_info.head
		elseif version_info.lazyvim_version_type == "commit" and version_info.lazyvim_version then
			target.mode = "commit"
			target.commit = version_info.lazyvim_version
		elseif version_info.lazyvim_version_type == "tag" and version_info.lazyvim_version then
			target.mode = "tag"
			target.tag = version_info.lazyvim_version
			target.latest_tag = version_info.lazyvim_version
			target.commit = remote_info.tags[version_info.lazyvim_version]
		elseif version_info.lazyvim_version == false or (version_info.lazyvim_version_type == "version" and version_info.lazyvim_version == false) then
			target.mode = "head"
			target.commit = remote_info.head
		else
			-- Default to HEAD for unspecified versions (like fresh plugin installs)
			-- This mirrors how users actually install plugins - they get latest unless pinned
			target.mode = "head"
			target.commit = remote_info.head
		end

		if not target.commit then
			target.commit = remote_info.head
		end

		if target.commit then
			target.prefetch_rev = target.commit
		elseif target.branch then
			target.prefetch_rev = target.branch
		elseif target.tag then
			target.prefetch_rev = target.tag
		end

		return target
	end

	local function resolve_plugin_versions(plugins_list, existing_lookup, remote_map)
		for _, plugin in ipairs(plugins_list) do
			if plugin.owner and plugin.repo then
				local repo_key = plugin.owner .. "/" .. plugin.repo
				local remote_info = remote_map[repo_key]
				if not remote_info then
					error("Missing remote metadata for " .. repo_key)
				end

				local existing = existing_lookup[plugin.name]
				local existing_info = existing and existing.version_info or nil
				local version_info = plugin.version_info or {}
				plugin.version_info = version_info

				print(string.format("    Resolving version info for %s...", plugin.name))

				local target = determine_target(plugin, remote_info)

				-- For branch-type versions, store the resolved commit as lazyvim_version
				-- This ensures reproducible builds by pinning to a specific commit
				if target.lazyvim_version_type == "branch" and target.commit then
					version_info.lazyvim_version = target.commit
					version_info.lazyvim_version_type = "commit"
					version_info.branch = target.branch  -- Keep original branch name for reference
				else
					version_info.lazyvim_version = target.lazyvim_version
					version_info.lazyvim_version_type = target.lazyvim_version_type
					version_info.branch = target.branch
				end
				version_info.tag = target.tag
				version_info.latest_tag = target.latest_tag
				if target.commit then
					version_info.commit = target.commit
				end

				local existing_commit = existing_info and existing_info.commit or nil
				local existing_sha = existing_info and existing_info.sha256 or nil

				if target.commit and existing_commit == target.commit and existing_sha then
					version_info.sha256 = existing_sha
					version_info.fetched_at = existing_info and existing_info.fetched_at or os.date("!%Y-%m-%dT%H:%M:%SZ")
					print(string.format("      ↺ Reusing cached prefetch (%s)", format_ref(target.commit)))
				else
					enqueue_prefetch(plugin, target, existing_info)
				end
			end
		end

		process_prefetch_queue()
	end

	local function process_prefetch_queue()
		if #prefetch_queue == 0 then
			return
		end

		print(string.format("=== Prefetching %d plugins (concurrency %d) ===", #prefetch_queue, PREFETCH_CONCURRENCY))

		local loop = vim.loop
		local results = {}
		local active = 0
		local next_index = 1
		local completed = false

		local function start_next()
			if next_index > #prefetch_queue then
				if active == 0 then
					completed = true
				end
				return
			end

			local task = prefetch_queue[next_index]
			next_index = next_index + 1
			active = active + 1

			local stdout_pipe = loop.new_pipe(false)
			local stderr_pipe = loop.new_pipe(false)
			local output_chunks = {}
			local error_chunks = {}
			local handle

			local function finalize(code)
				stdout_pipe:close()
				stderr_pipe:close()
				if handle and not handle:is_closing() then
					handle:close()
				end

				active = active - 1
				table.insert(results, {
					task = task,
					code = code,
					stdout = table.concat(output_chunks),
					stderr = table.concat(error_chunks),
				})

				start_next()
				if next_index > #prefetch_queue and active == 0 then
					completed = true
				end
			end

			handle = loop.spawn("nix-prefetch-git", {
				args = task.args,
				stdio = { nil, stdout_pipe, stderr_pipe },
			}, finalize)

			if not handle then
				table.insert(results, {
					task = task,
					code = -1,
					stdout = "",
					stderr = "failed to spawn nix-prefetch-git",
				})
				active = active - 1
				start_next()
				if next_index > #prefetch_queue and active == 0 then
					completed = true
				end
				return
			end

			loop.read_start(stdout_pipe, function(err, data)
				if err then
					table.insert(error_chunks, err)
				elseif data then
					table.insert(output_chunks, data)
				end
			end)

			loop.read_start(stderr_pipe, function(err, data)
				if err then
					table.insert(error_chunks, err)
				elseif data then
					table.insert(error_chunks, data)
				end
			end)
		end

		for _ = 1, math.min(PREFETCH_CONCURRENCY, #prefetch_queue) do
			start_next()
		end

		vim.wait(1e8, function()
			return completed
		end, 50)

		for _, result in ipairs(results) do
			local task = result.task
			local plugin = task.plugin
			local target = task.target
			local existing = task.existing
			local version_info = plugin.version_info

			if result.code ~= 0 then
				error(string.format("nix-prefetch-git failed for %s: %s", plugin.name, result.stderr))
			end

			local ok, data = pcall(vim.json.decode, result.stdout)
			if not ok or not data or not data.rev or not data.sha256 then
				error(string.format("Invalid nix-prefetch-git output for %s", plugin.name))
			end

			local commit = data.rev
			local sha256 = data.sha256
			local version_changed = not (existing and existing.commit == commit)

			version_info.commit = commit
			version_info.sha256 = sha256

			if version_changed or not (existing and existing.fetched_at) then
				version_info.fetched_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
			else
				version_info.fetched_at = existing.fetched_at
			end

			if target.tag then
				version_info.tag = target.tag
				version_info.latest_tag = target.latest_tag or target.tag
				version_info.branch = nil
			elseif target.branch then
				version_info.branch = target.branch
				version_info.tag = nil
				version_info.latest_tag = target.latest_tag
			else
				version_info.tag = nil
				version_info.branch = nil
				version_info.latest_tag = target.latest_tag
			end

			if version_changed then
				print(string.format("      ✓ %s updated to %s", plugin.name, format_ref(commit)))
			else
				print(string.format("      ✓ %s verified at %s (unchanged)", plugin.name, format_ref(commit)))
			end
		end
	end

	local function guess_nixpkg_name(plugin_name)
		local owner, repo_name = plugin_name:match("^([^/]+)/(.+)$")
		if not owner or not repo_name then
			return nil
		end

		if repo_name:match("%.nvim$") then
			local base_name = repo_name:gsub("%.nvim$", "")
			return base_name .. "-nvim"
		elseif repo_name:match("%-nvim$") then
			return repo_name
		elseif repo_name:match("^nvim%-") then
			return repo_name
		else
			return repo_name:gsub("%-", "_"):gsub("%.", "_")
		end
	end

	local function evaluate_nix_attr_presence(candidates)
		if #candidates == 0 then
			return {}
		end

		local quoted = {}
		for _, name in ipairs(candidates) do
			table.insert(quoted, string.format('"%s"', name))
		end

		local expr = string.format(
			"let pkgs = import <nixpkgs> {}; names = [ %s ]; in builtins.listToAttrs (map (name: { name = name; value = builtins.hasAttr name pkgs.vimPlugins; }) names)",
			table.concat(quoted, " ")
		)

		-- Redirect stderr to a temp file to prevent JSON contamination
		local stderr_file = vim.fn.tempname()
		local cmd = string.format("nix eval --json --impure --expr '%s' 2>%s", expr:gsub("'", "'\\''"), stderr_file)
		local result = vim.fn.system(cmd)
		local stderr_content = vim.fn.readfile(stderr_file)
		vim.fn.delete(stderr_file)

		if vim.v.shell_error ~= 0 then
			error(string.format(
				"Failed to evaluate nix expression (exit code %d)\nExpression: %s\nStdout: %s\nStderr: %s",
				vim.v.shell_error,
				expr,
				result,
				table.concat(stderr_content, "\n")
			))
		end

		local ok, decoded = pcall(vim.json.decode, result)
		if not ok then
			error(string.format(
				"Failed to parse nix eval JSON output\nRaw output: %s\nParse error: %s\nStderr: %s",
				result,
				tostring(decoded),
				table.concat(stderr_content, "\n")
			))
		end

		return decoded
	end

	local function finalize_mappings(plugins_list)
		local unmapped = {}
		local mapped_count = 0
		local multi_count = 0
		local candidate_set = {}
		local candidate_list = {}

		for _, plugin in ipairs(plugins_list) do
			if plugin.multiModule then
				multi_count = multi_count + 1
			end

			if existing_mappings[plugin.name] ~= nil or multi_module_mappings[plugin.name] ~= nil then
				mapped_count = mapped_count + 1
				plugin.mapped_status = "explicit"
			else
				local candidate = guess_nixpkg_name(plugin.name)
				plugin.nixpkgs_candidate = candidate
				if candidate and not candidate_set[candidate] then
					candidate_set[candidate] = true
					table.insert(candidate_list, candidate)
				end
			end
		end

		local attr_results = evaluate_nix_attr_presence(candidate_list)

		for _, plugin in ipairs(plugins_list) do
			if plugin.mapped_status ~= "explicit" then
				local candidate = plugin.nixpkgs_candidate
				if candidate and attr_results[candidate] then
					mapped_count = mapped_count + 1
					plugin.mapped_status = "auto"
				else
					plugin.mapped_status = "unmapped"
					table.insert(unmapped, plugin.name)
				end
			end
		end

		extraction_report.mapped_plugins = mapped_count
		extraction_report.unmapped_plugins = #unmapped
		extraction_report.multi_module_plugins = multi_count

		return unmapped
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
				end

				local repo_key = (owner or "") .. "/" .. (repo or "")
				repo_index[repo_key] = {
					owner = owner,
					repo = repo,
					url = string.format("https://github.com/%s/%s", owner, repo),
				}

				table.insert(plugins, plugin_info)
			end
		elseif type(spec) == "table" then
			-- Skip optional plugins
			if spec.optional == true then
				print("    Skipping optional plugin: " .. (spec[1] or spec.name or "unknown"))
				return
			end

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
				end

				local repo_key = plugin_info.owner .. "/" .. plugin_info.repo
				repo_index[repo_key] = {
					owner = plugin_info.owner,
					repo = plugin_info.repo,
					url = string.format("https://github.com/%s/%s", plugin_info.owner, plugin_info.repo),
				}

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
	local function extract_plugins_from_extra(extra_path, relative_path, preloaded_content)
		local content = preloaded_content
		if not content then
			local file = io.open(extra_path, "r")
			if not file then
				return {}
			end
			content = file:read("*all")
			file:close()
		end

		-- Create a safe environment for loading the extra
		local function noop(...) return nil end
		local function const_zero(...) return 0 end
		local function const_false(...) return false end
		local function const_empty_string(...) return "" end

		local function stub_callable(return_value)
			return function()
				return return_value
			end
		end

		local function stub_function()
			return function()
				return nil
			end
		end

		local env = {
			pairs = pairs,
			ipairs = ipairs,
			onumber = tonumber,
			tostring = tostring,
			type = type,
			table = table,
			string = string,
			math = math,
			LazyVim = {
				has = const_false,
				has_extra = const_false,
				on_very_lazy = noop,
				memoize = function(_, fn) return fn end,
				cmp = setmetatable({}, { __index = function() return {} end }),
				pick = setmetatable({}, { __index = stub_function }),
				util = setmetatable({}, { __index = stub_function }),
			},
			vim = {
				fn = setmetatable({
					has = const_zero,
					executable = const_zero,
					is_win = const_zero,
					isdirectory = const_zero,
					filereadable = const_zero,
					line = const_zero,
					col = const_zero,
					stdpath = const_empty_string,
					expand = const_empty_string,
					trim = const_empty_string,
					tolower = const_empty_string,
					glob = const_empty_string,
					json_decode = function(_, _) return {} end,
					input = const_empty_string,
				}, {
					__index = function()
						return const_zero
					end,
				}),
				cmd = noop,
				g = {},
				api = setmetatable({}, { __index = function() return noop end }),
				loop = setmetatable({}, { __index = function() return noop end }),
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
				-- Skip optional plugins
				if item.optional == true then
					print("    Skipping optional plugin: " .. item[1])
					goto continue
				end

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
						end

						local repo_key = plugin_info.owner .. "/" .. plugin_info.repo
						repo_index[repo_key] = {
							owner = plugin_info.owner,
							repo = plugin_info.repo,
							url = string.format("https://github.com/%s/%s", plugin_info.owner, plugin_info.repo),
						}

						table.insert(plugins, plugin_info)
					end
				end
			end
			::continue::
		end

		return plugins
	end

	-- Function to scan LazyVim extras directory recursively
	local function scan_lazyvim_extras(lazyvim_path, entries_override)
		local extras_path = lazyvim_path .. "/lua/lazyvim/plugins/extras"
		local extras_plugins = {}

		local function add_from_entry(entry)
			local relative_path = entry.relative
			print("  Processing extra: " .. relative_path)
			local plugins = extract_plugins_from_extra(entry.path, relative_path, entry.content)
			for _, plugin in ipairs(plugins) do
				table.insert(extras_plugins, plugin)
			end
		end

		print("=== Scanning LazyVim extras ===")

		if entries_override then
			for _, entry in ipairs(entries_override) do
				if entry.path:sub(1, #extras_path) == extras_path then
					add_from_entry(entry)
				end
			end
		else
			local handle = io.popen("find '" .. extras_path .. "' -name '*.lua' -type f 2>/dev/null")
			if not handle then
				print("Warning: Could not scan extras directory: " .. extras_path)
			else
				for line in handle:lines() do
					local relative_path = line:sub(#extras_path + 2)
					if relative_path and relative_path ~= "" then
						add_from_entry({ path = line, relative = relative_path, content = nil })
					end
				end
				handle:close()
			end
		end

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
	local extras_plugins = scan_lazyvim_extras(lazyvim_path, shared_extras_entries)
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

				local repo_key = user_plugin.owner .. "/" .. user_plugin.repo
				repo_index[repo_key] = {
					owner = user_plugin.owner,
					repo = user_plugin.repo,
					url = string.format("https://github.com/%s/%s", user_plugin.owner, user_plugin.repo),
				}

				table.insert(plugins, user_plugin)
			else
				print(string.format("Skipping user plugin %s (already exists in core)", user_plugin.name))
			end
		end
	else
		print("No user plugins found")
	end

	local remote_map = fetch_remote_refs(repo_index)
	resolve_plugin_versions(plugins, existing_plugins, remote_map)

	local unmapped_plugins = finalize_mappings(plugins)

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
