-- Plugin Mapping Suggestion Engine
-- Analyzes unmapped plugins and suggests potential nixpkgs mappings

local M = {}

-- Known naming patterns for automatic suggestion
local NAMING_PATTERNS = {
	-- Standard patterns (nixpkgs uses hyphens, not underscores)
	{
		pattern = "(.+)/(.+)%.nvim$",
		transform = function(_, name)
			return name .. "-nvim"
		end,
	},
	{
		pattern = "(.+)/(.+)%-nvim$",
		transform = function(_, name)
			return name .. "-nvim"
		end,
	},
	{
		pattern = "(.+)/nvim%-(.+)$",
		transform = function(_, name)
			return "nvim-" .. name
		end,
	},
	{
		pattern = "(.+)/(.+)$",
		transform = function(_, name)
			return name
		end,
	},
}

-- Multi-module detection patterns
local MULTI_MODULE_PATTERNS = {
	"^(.+)/mini%.(.+)$", -- echasnovski/mini.ai -> mini-nvim + ai module
	-- Note: Removed generic pattern to avoid false positives with .nvim plugins
}

-- Known multi-module base packages
local MULTI_MODULE_BASES = {
	["echasnovski/mini"] = "mini-nvim",
	-- Add more as discovered
}

-- Function to verify if a nixpkgs package exists
function M.verify_nixpkgs_package(package_name)
	-- Try to evaluate the package in nixpkgs (use nixos-unstable)
	local cmd = string.format(
		"nix eval --impure --expr 'let pkgs = import (fetchTarball \"https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz\") {}; in pkgs.vimPlugins.%s or null' 2>/dev/null",
		package_name
	)
	local handle = io.popen(cmd)
	if not handle then
		return false, "failed to execute nix command"
	end

	local result = handle:read("*all")
	local success = handle:close()

	-- Check if the result is not null (package exists)
	if success and result and not result:match("null") and result:match("«derivation") then
		return true, "verified"
	elseif result and result:match("null") then
		return false, "package not found in nixpkgs.vimPlugins"
	else
		return false, "unable to verify"
	end
end

-- Function to suggest nixpkgs package name
function M.suggest_nixpkgs_name(plugin_name, verify)
	local suggestions = {}

	for _, pattern_info in ipairs(NAMING_PATTERNS) do
		local owner, name = plugin_name:match(pattern_info.pattern)
		if owner and name then
			local suggestion = pattern_info.transform(owner, name)
			local suggestion_info = {
				name = suggestion,
				confidence = "medium",
				pattern = pattern_info.pattern,
				reasoning = string.format("Applied pattern %s to %s", pattern_info.pattern, plugin_name),
			}

			-- Optionally verify the package exists
			if verify then
				local exists, verify_msg = M.verify_nixpkgs_package(suggestion)
				suggestion_info.verified = exists
				suggestion_info.verify_message = verify_msg

				-- Boost confidence if verified
				if exists then
					suggestion_info.confidence = "high"
				else
					suggestion_info.confidence = "low"
				end
			end

			table.insert(suggestions, suggestion_info)
		end
	end

	return suggestions
end

-- Function to detect multi-module plugins
function M.detect_multi_module(plugin_name)
	for _, pattern in ipairs(MULTI_MODULE_PATTERNS) do
		local owner_or_base, module = plugin_name:match(pattern)
		if owner_or_base and module then
			-- Check if it matches known multi-module bases
			local base_key = owner_or_base
			if pattern:match("mini") then
				base_key = owner_or_base .. "/mini"
			end

			local base_package = MULTI_MODULE_BASES[base_key]
			if base_package then
				return {
					is_multi_module = true,
					base_package = base_package,
					module_name = module,
					base_repo = base_key == "echasnovski/mini" and "echasnovski/mini.nvim"
						or (owner_or_base .. "/" .. module:match("^(.+)%.") or owner_or_base),
					confidence = "high",
					reasoning = string.format("Matches known multi-module pattern for %s", base_key),
				}
			end
		end
	end

	return { is_multi_module = false }
end

-- Function to analyze a list of unmapped plugins and generate suggestions
function M.analyze_unmapped_plugins(unmapped_plugins, verify_packages)
	local analysis = {
		total_unmapped = #unmapped_plugins,
		mapping_suggestions = {},
		multi_module_candidates = {},
		manual_review_needed = {},
		verification_enabled = verify_packages or false,
	}

	for _, plugin_name in ipairs(unmapped_plugins) do
		local nixpkgs_suggestions = M.suggest_nixpkgs_name(plugin_name, verify_packages)
		local multi_module_info = M.detect_multi_module(plugin_name)

		local plugin_analysis = {
			name = plugin_name,
			nixpkgs_suggestions = nixpkgs_suggestions,
			multi_module = multi_module_info,
		}

		if multi_module_info.is_multi_module then
			table.insert(analysis.multi_module_candidates, plugin_analysis)
		elseif #nixpkgs_suggestions > 0 then
			table.insert(analysis.mapping_suggestions, plugin_analysis)
		else
			table.insert(analysis.manual_review_needed, plugin_analysis)
		end
	end

	return analysis
end

-- Function to generate mapping file updates
function M.generate_mapping_updates(analysis)
	local updates = {}

	-- Generate standard mapping updates
	for _, suggestion in ipairs(analysis.mapping_suggestions) do
		if #suggestion.nixpkgs_suggestions > 0 then
			-- Find the best verified suggestion, or fallback to first
			local best_suggestion = suggestion.nixpkgs_suggestions[1]
			for _, sugg in ipairs(suggestion.nixpkgs_suggestions) do
				if sugg.verified then
					best_suggestion = sugg
					break
				end
			end

			table.insert(updates, {
				type = "standard",
				plugin_name = suggestion.name,
				nixpkgs_name = best_suggestion.name,
				confidence = best_suggestion.confidence,
				verified = best_suggestion.verified,
				line = string.format('  "%s" = "%s";', suggestion.name, best_suggestion.name),
			})
		end
	end

	-- Generate multi-module mapping updates
	for _, candidate in ipairs(analysis.multi_module_candidates) do
		if candidate.multi_module.confidence == "high" then
			table.insert(updates, {
				type = "multi_module",
				plugin_name = candidate.name,
				base_package = candidate.multi_module.base_package,
				module_name = candidate.multi_module.module_name,
				confidence = candidate.multi_module.confidence,
				line = string.format(
					'  "%s" = { package = "%s"; module = "%s"; };',
					candidate.name,
					candidate.multi_module.base_package,
					candidate.multi_module.module_name
				),
			})
		end
	end

	return updates
end

-- Function to format analysis report
function M.format_report(analysis)
	local report = {}

	table.insert(report, "# Plugin Mapping Analysis Report")
	table.insert(report, string.format("Generated: %s", os.date("%Y-%m-%d %H:%M:%S")))
	table.insert(report, string.format("Total unmapped plugins: %d", analysis.total_unmapped))
	if analysis.verification_enabled then
		table.insert(report, "Package verification: ENABLED")
	else
		table.insert(report, "Package verification: DISABLED (use --verify to enable)")
	end
	table.insert(report, "")

	-- Separate verified and unverified suggestions
	local verified_mappings = {}
	local failed_mappings = {}

	for _, suggestion in ipairs(analysis.mapping_suggestions) do
		local found_verified = false
		local verified_mapping = nil

		-- Find the first verified mapping
		for _, nixpkg in ipairs(suggestion.nixpkgs_suggestions) do
			if nixpkg.verified then
				verified_mapping = nixpkg
				found_verified = true
				break
			end
		end

		if found_verified and verified_mapping then
			table.insert(verified_mappings, {
				plugin = suggestion.name,
				mapping = verified_mapping,
			})
		else
			-- Collect all failed attempts for this plugin
			local failed_attempts = {}
			for _, nixpkg in ipairs(suggestion.nixpkgs_suggestions) do
				if nixpkg.verified == false then
					table.insert(failed_attempts, nixpkg.name)
				end
			end

			if #failed_attempts > 0 then
				table.insert(failed_mappings, {
					plugin = suggestion.name,
					attempts = failed_attempts,
				})
			end
		end
	end

	-- Format successful mappings
	if #verified_mappings > 0 then
		table.insert(report, "## ✅ Verified Mappings")
		table.insert(report, "")
		table.insert(report, "Add these to `plugin-mappings.nix`:")
		table.insert(report, "")
		table.insert(report, "```nix")
		for _, item in ipairs(verified_mappings) do
			table.insert(report, string.format('  "%s" = "%s";', item.plugin, item.mapping.name))
		end
		table.insert(report, "```")
		table.insert(report, "")
	end

	-- Format failed mappings
	if #failed_mappings > 0 then
		table.insert(report, "## ❌ Failed Mappings")
		table.insert(report, "")
		table.insert(report, "These plugins could not be automatically mapped:")
		table.insert(report, "")
		for _, item in ipairs(failed_mappings) do
			table.insert(report, string.format("- **%s**", item.plugin))
			table.insert(report, string.format("  - Tried: %s", table.concat(item.attempts, ", ")))
		end
		table.insert(report, "")
	end

	-- If no verification was done, show all suggestions
	if not analysis.verification_enabled and #analysis.mapping_suggestions > 0 then
		table.insert(report, "## Suggested Mappings (Unverified)")
		table.insert(report, "")
		table.insert(report, "Run with `--verify` to check which packages exist in nixpkgs.")
		table.insert(report, "")
		for _, suggestion in ipairs(analysis.mapping_suggestions) do
			if #suggestion.nixpkgs_suggestions > 0 then
				local best = suggestion.nixpkgs_suggestions[1]
				table.insert(report, string.format('  "%s" = "%s";', suggestion.name, best.name))
			end
		end
		table.insert(report, "")
	end

	if #analysis.multi_module_candidates > 0 then
		table.insert(report, "## Multi-Module Plugin Candidates")
		for _, candidate in ipairs(analysis.multi_module_candidates) do
			table.insert(report, string.format("- **%s**", candidate.name))
			table.insert(report, string.format("  - Base package: `%s`", candidate.multi_module.base_package))
			table.insert(report, string.format("  - Module: `%s`", candidate.multi_module.module_name))
			table.insert(report, string.format("  - Confidence: %s", candidate.multi_module.confidence))
			table.insert(report, string.format("  - %s", candidate.multi_module.reasoning))
			table.insert(report, "")
		end
	end

	-- Add manual review section at the end for completeness
	if #analysis.manual_review_needed > 0 then
		table.insert(report, "## 🔍 Manual Review Needed")
		table.insert(report, "")
		table.insert(report, "No automatic suggestions available for:")
		table.insert(report, "")
		for _, plugin in ipairs(analysis.manual_review_needed) do
			table.insert(report, string.format("- **%s**", plugin.name))
		end
		table.insert(report, "")
	end

	return table.concat(report, "\n")
end

return M
