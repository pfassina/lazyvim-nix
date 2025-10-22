#!/usr/bin/env lua

-- LazyVim Dependencies Extractor
-- Creates a dependencies file with tools, runtimes, and nixpkgs mappings

local function read_file(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*all")
    file:close()
    return content
end

-- Language identifiers and config keys that should NOT be treated as system dependencies
local EXCLUDED_IDENTIFIERS = {
    -- Language names
    "angular", "astro", "bash", "c", "c_sharp", "clojure", "cmake", "cpp", "css", "dart",
    "dockerfile", "eex", "elixir", "elm", "erlang", "fsharp", "go", "graphql", "haskell",
    "hcl", "heex", "html", "java", "javascript", "jsdoc", "json", "json5", "jsonc", "julia",
    "kotlin", "latex", "lua", "luadoc", "luap", "markdown", "markdown_inline", "ninja", "nix",
    "nu", "nushell", "ocaml", "php", "python", "query", "r", "rasi", "regex", "rego", "rnoweb",
    "ron", "rst", "ruby", "rust", "scala", "scss", "sql", "svelte", "thrift", "toml", "tsx",
    "typescript", "typst", "vim", "vimdoc", "vue", "xml", "yaml", "zig", "twig", "solidity",

    -- LSP server names (these are configured, not system deps)
    "angularls", "ansiblels", "bashls", "dartls", "dockerls", "elixirls", "elmls", "erlangls",
    "julials", "kotlin_language_server", "nil_ls", "ocamllsp", "prismals", "r_language_server",
    "ruby_lsp", "solidity_ls", "terraformls", "tsserver", "vue_ls", "yamlls", "bacon_ls",
    "twiggy_language_server", "jdtls", "phpactor", "marksman", "texlab", "helm_ls", "neocmake",

    -- Configuration keys and internal identifiers
    "FileType", "RUFF_TRACE", "arguments", "before_init", "buf_name", "capabilities", "chrome",
    "cmd_env", "codelenses", "command", "completionmode", "copilot", "count", "desc", "diagnostics",
    "diff", "dynamicRegistration", "ember", "enabled", "file_name", "filetypes", "filetypes_exclude",
    "foldingRange", "gc_details", "generate", "git_config", "git_rebase", "gitattributes", "gitcommit",
    "gitignore", "glimmer", "glimmer_javascript", "glimmer_typescript", "gomod", "gosum", "gowork",
    "http", "keys", "lineFoldingOnly", "lint", "lsp", "missingrefs", "mode", "msedge", "node",
    "null-ls", "nvimtools/none-ls.nvim", "params", "printf", "regenerate_cgo", "root_markers",
    "run_govulncheck", "schemas", "settings", "silent", "test", "textDocument", "tidy",
    "upgrade_dependency", "vendor", "workingDirectories", "bibtex"
}

-- Create lookup table for faster exclusion checks
local excluded_lookup = {}
for _, item in ipairs(EXCLUDED_IDENTIFIERS) do
    excluded_lookup[item] = true
end

-- Check if a tool name should be excluded
local function should_exclude_tool(tool_name)
    -- Never exclude known core LazyVim tools
    local core_tools = {"git", "rg", "fd", "fdfind", "lazygit", "fzf", "curl"}
    for _, core_tool in ipairs(core_tools) do
        if tool_name == core_tool then
            return false
        end
    end

    return excluded_lookup[tool_name] or
           tool_name:match("^%u+$") or  -- All caps (like RUFF_TRACE)
           tool_name:match("^[a-z_]+$") and #tool_name < 3  -- Very short generic names (only 1-2 chars)
end

-- Extract dependencies from LazyVim health.lua
local function extract_core_dependencies(lazyvim_path)
    local health_path = lazyvim_path .. "/lua/lazyvim/health.lua"
    local content = read_file(health_path)

    if not content then
        print("Warning: Could not read LazyVim health.lua")
        return {}
    end

    local dependencies = {}

    -- Look for the dependency list in health.lua - LazyVim specific pattern
    -- Line looks like: for _, cmd in ipairs({ "git", "rg", { "fd", "fdfind" }, "lazygit", "fzf", "curl" }) do
    local deps_pattern = 'ipairs%s*%(%s*{%s*(.-)%s*}%s*%)'
    local deps_list = content:match(deps_pattern)

    if deps_list then
        print("Found dependency list: " .. deps_list:sub(1, 100) .. "...")

        -- First pass: extract all individual quoted strings
        for dep in deps_list:gmatch('"([^"]+)"') do
            if not should_exclude_tool(dep) then
                table.insert(dependencies, dep)
            end
        end

        -- Remove duplicates (since alternatives like "fd", "fdfind" both get added)
        local unique_deps = {}
        local seen = {}
        for _, dep in ipairs(dependencies) do
            if not seen[dep] then
                seen[dep] = true
                table.insert(unique_deps, dep)
            end
        end
        dependencies = unique_deps

        print("Extracted individual dependencies: " .. table.concat(dependencies, ", "))
    end

    -- Fallback: manual list based on known LazyVim dependencies
    if #dependencies == 0 then
        print("Warning: Could not parse dependencies from health.lua, using fallback")
        dependencies = { "git", "rg", "fd", "lazygit", "fzf", "curl" }
    end

    print(string.format("Extracted %d core dependencies from LazyVim health.lua", #dependencies))
    return dependencies
end

-- Extract executable checks from a Lua file
local function extract_executables_from_file(file_path, relative_path)
    local content = read_file(file_path)
    if not content then
        return {}
    end

    local executables = {}

    -- Pattern 1: vim.fn.executable("command") == 1
    for executable in content:gmatch('vim%.fn%.executable%s*%(%s*"([^"]+)"%s*%)%s*==%s*1') do
        if not should_exclude_tool(executable) then
            table.insert(executables, executable)
        end
    end

    -- Pattern 2: vim.fn.executable('command') == 1
    for executable in content:gmatch("vim%.fn%.executable%s*%(%s*'([^']+)'%s*%)%s*==%s*1") do
        if not should_exclude_tool(executable) then
            table.insert(executables, executable)
        end
    end

    -- Pattern 3: if vim.fn.executable("command")
    for executable in content:gmatch('if%s+vim%.fn%.executable%s*%(%s*"([^"]+)"%s*%)') do
        if not should_exclude_tool(executable) then
            table.insert(executables, executable)
        end
    end

    -- Remove duplicates
    local unique_executables = {}
    local seen = {}
    for _, exec in ipairs(executables) do
        if not seen[exec] then
            seen[exec] = true
            table.insert(unique_executables, exec)
        end
    end

    if #unique_executables > 0 then
        print(string.format("  Found %d executables in %s: %s",
                          #unique_executables, relative_path, table.concat(unique_executables, ", ")))
    end

    return unique_executables
end

-- Extract configured tools (LSP servers, formatters, etc.) from file content
local function extract_configured_tools(file_content)
    local tools = {}

    -- Extract LSP servers from opts.servers
    for servers_block in file_content:gmatch('servers%s*=%s*{([^}]*)}') do
        for server_name in servers_block:gmatch('([%w_%-]+)%s*=') do
            if not should_exclude_tool(server_name) then
                table.insert(tools, server_name)
            end
        end
    end

    -- Extract Mason ensure_installed
    for ensure_block in file_content:gmatch('ensure_installed[^{]*{([^}]*)}') do
        for tool in ensure_block:gmatch('"([^"]+)"') do
            if not should_exclude_tool(tool) then
                table.insert(tools, tool)
            end
        end
    end

    -- Extract from table.insert patterns
    for tool in file_content:gmatch('table%.insert%(opts%.ensure_installed,%s*"([^"]+)"') do
        if not should_exclude_tool(tool) then
            table.insert(tools, tool)
        end
    end

    return tools
end

-- Scan LazyVim extras directory for dependencies
local function extract_extra_dependencies(lazyvim_path)
    local extras_path = lazyvim_path .. "/lua/lazyvim/plugins/extras"
    local extras_deps = {}

    -- Helper function to scan directory recursively
    local function scan_directory(dir_path, base_path)
        local handle = io.popen("find '" .. dir_path .. "' -name '*.lua' -type f 2>/dev/null")
        if not handle then
            print("Warning: Could not scan extras directory: " .. dir_path)
            return
        end

        for file_path in handle:lines() do
            -- Get relative path from extras directory
            local relative_path = file_path:sub(#base_path + 2) -- +2 to remove leading slash
            if relative_path and relative_path ~= "" then
                -- Convert file path to extra module name
                local extra_name = relative_path:gsub("%.lua$", ""):gsub("/", ".")

                -- Extract executable checks from the file
                local executables = extract_executables_from_file(file_path, relative_path)

                -- Extract all information from the file
                local file_content = read_file(file_path)
                if file_content then
                    -- Extract configured tools (LSPs, formatters, etc.)
                    local configured_tools = extract_configured_tools(file_content)

                    -- Store extracted data if we found tools
                    if #executables > 0 or #configured_tools > 0 then
                        local all_tools = {}
                        for _, tool in ipairs(executables) do
                            table.insert(all_tools, tool)
                        end
                        for _, tool in ipairs(configured_tools) do
                            table.insert(all_tools, tool)
                        end

                        -- Remove duplicates
                        local unique_tools = {}
                        local seen = {}
                        for _, tool in ipairs(all_tools) do
                            if not seen[tool] then
                                seen[tool] = true
                                table.insert(unique_tools, tool)
                            end
                        end

                        if #unique_tools > 0 then
                            extras_deps[extra_name] = unique_tools

                            print(string.format("  Found %d tools in %s: %s",
                                              #unique_tools, relative_path,
                                              table.concat(unique_tools, ", "):sub(1, 60) ..
                                              (#table.concat(unique_tools, ", ") > 60 and "..." or "")))
                        end
                    end
                end
            end
        end
        handle:close()
    end

    print("=== Scanning LazyVim extras for dependencies ===")
    scan_directory(extras_path, extras_path)

    local total_extras = 0
    for _ in pairs(extras_deps) do
        total_extras = total_extras + 1
    end
    print(string.format("Found tools in %d LazyVim extras", total_extras))

    return extras_deps
end

-- Get unique list of all tools from extracted dependencies
local function get_all_tools(core_deps, extra_deps)
    local all_tools = {}
    local seen = {}

    -- Add core dependencies
    for _, tool in ipairs(core_deps) do
        if not seen[tool] then
            seen[tool] = true
            table.insert(all_tools, tool)
        end
    end

    -- Add tools from extras
    for _, tools in pairs(extra_deps) do
        for _, tool in ipairs(tools) do
            if not seen[tool] then
                seen[tool] = true
                table.insert(all_tools, tool)
            end
        end
    end

    table.sort(all_tools)
    return all_tools
end

-- Parse YAML-like content from Mason registry package files
local function parse_mason_package(file_path)
    local content = read_file(file_path)
    if not content then
        return nil
    end

    local package_info = {}

    -- Extract name
    local name = content:match("name:%s*([^\r\n]+)")
    if name then
        package_info.name = name:gsub("^%s+", ""):gsub("%s+$", "")
    end

    -- Extract source.id to determine package type
    local source_id = content:match("source:%s*\r?\n%s*id:%s*([^\r\n]+)")
    if source_id then
        package_info.source_id = source_id:gsub("^%s+", ""):gsub("%s+$", "")

        -- Extract package type from source.id
        local pkg_type = source_id:match("^pkg:([^/]+)")
        if pkg_type then
            package_info.package_type = pkg_type
        end
    end

    return package_info
end

-- Map package types to runtime requirements
local function get_runtime_for_package_type(package_type)
    local type_to_runtime = {
        npm = {"nodejs", "npm"},
        cargo = {"cargo", "rustc"},
        gem = {"ruby", "gem"},
        pip = {"python3", "pip"},
        pypi = {"python3", "pip"},
        go = {"go"},
        golang = {"go"},
        composer = {"php", "composer"},
        nuget = {"dotnet-sdk"},
        opam = {"ocaml", "opam"},
        luarocks = {"lua", "luarocks"}
    }

    return type_to_runtime[package_type] or {}
end

-- Extract runtime dependencies for tools using Mason registry
local function get_runtime_dependencies(mason_path, tools)
    local runtime_deps = {}

    for _, tool in ipairs(tools) do
        local package_path = mason_path .. "/packages/" .. tool .. "/package.yaml"
        local package_info = parse_mason_package(package_path)

        if package_info and package_info.package_type then
            local runtimes = get_runtime_for_package_type(package_info.package_type)
            if #runtimes > 0 then
                runtime_deps[tool] = runtimes
            end
        end
    end

    return runtime_deps
end

-- Verify if a nixpkgs package exists
local function verify_nixpkg_exists(nixpkg_path)
    -- Use nix-instantiate to check if package exists
    local cmd = string.format("nix-instantiate --eval --expr 'with import <nixpkgs> {}; %s.name or \"%s\"' 2>/dev/null", nixpkg_path, nixpkg_path)
    local handle = io.popen(cmd)
    if not handle then
        return false
    end

    local result = handle:read("*line")
    local exit_code = handle:close()

    -- If command succeeded and returned something (not just the path), package exists
    return exit_code and result and result ~= '""' and result ~= ("\"" .. nixpkg_path .. "\"")
end

-- Nixpkgs package resolution strategies with verification
local function resolve_package_name(dep_name)
    -- Strategy 1: Package managers should not be mapped (they're not standalone packages)
    local package_managers = {"pip", "npm", "composer", "luarocks", "opam", "gem"}
    for _, pm in ipairs(package_managers) do
        if dep_name == pm then
            return nil  -- Don't map package managers
        end
    end

    -- Strategy 2: Direct exact matches (known package name differences)
    local direct_mappings = {
        -- Core LazyVim tools
        rg = "ripgrep",
        fdfind = "fd",
        fd = "fd",
        git = "git",
        fzf = "fzf",
        curl = "curl",
        lazygit = "lazygit",

        -- Language servers and tools
        delta = "delta",
        rust_analyzer = "rust-analyzer",
        ["rust-analyzer"] = "rust-analyzer",
        shellcheck = "shellcheck",
        hadolint = "hadolint",
        gitui = "gitui",
        taplo = "taplo",
        stylua = "stylua",
        clangd = "clang-tools",
        helm = "kubernetes-helm",
        terraform = "terraform",
        gleam = "gleam",
        tinymist = "tinymist",
        ["haskell-language-server"] = "haskell-language-server",

        -- Go tools with direct names
        gopls = "gopls",
        gofumpt = "gofumpt",
        goimports = "go",  -- goimports is part of the go package
        gomodifytags = "gomodifytags",
        impl = "impl",
        ["golangci-lint"] = "golangci-lint",
        delve = "delve",
        regols = "regols",

        -- Python tools
        black = "python3Packages.black",
        ruff = "python3Packages.ruff",
        sqlfluff = "sqlfluff",  -- Top-level package

        -- Node packages (with correct names)
        prettier = "nodePackages.prettier",
        eslint = "nodePackages.eslint",

        -- Debug adapters
        codelldb = "vscode-extensions.vadimcn.vscode-lldb",

        -- Runtime packages
        nodejs = "nodejs",
        cargo = "cargo",
        rustc = "rustc",
        ruby = "ruby",
        python3 = "python3",
        go = "go",
        php = "php",
        ["dotnet-sdk"] = "dotnet-sdk",
        lua = "lua",
        ocaml = "ocaml"
    }

    if direct_mappings[dep_name] then
        return direct_mappings[dep_name]
    end

    -- Strategy 3: Top-level tools that exist directly
    local toplevel_tools = {
        ["ansible-lint"] = "ansible-lint",  -- Top-level package
        ["tflint"] = "tflint",
        ["ktlint"] = "ktlint"
    }
    for tool, nixpkg_name in pairs(toplevel_tools) do
        if dep_name == tool then
            return nixpkg_name
        end
    end

    -- Strategy 4: Python packages (specific patterns that actually exist)
    local python_tools = {
        ["cmakelang"] = "cmakelang",       -- CMake formatting tools
        ["cmakelint"] = "cmakelint"        -- CMake linting
    }
    for tool, nixpkg_name in pairs(python_tools) do
        if dep_name == tool then
            return "python3Packages." .. nixpkg_name
        end
    end

    -- Strategy 5: Node packages (with verified names)
    local node_tools = {
        ["markdownlint-cli2"] = "markdownlint-cli2",  -- Use hyphens, not underscores
        ["markdown-toc"] = "markdown_toc"
    }
    for tool, nixpkg_name in pairs(node_tools) do
        if dep_name == tool then
            return "nodePackages." .. nixpkg_name
        end
    end

    -- Strategy 6: Ruby gems (be conservative)
    local ruby_tools = {
        ["erb-formatter"] = "erb_formatter"
    }
    for tool, nixpkg_name in pairs(ruby_tools) do
        if dep_name == tool then
            return "rubyPackages." .. nixpkg_name
        end
    end

    -- Strategy 7: Common transformations
    if dep_name:match("^node") then return "nodejs" end
    if dep_name == "python" then return "python3" end

    return nil  -- Could not resolve
end

-- Resolve and verify a package name, returning verified mapping or nil
local function resolve_and_verify_package(dep_name, verification_report)
    local suggested_nixpkg = resolve_package_name(dep_name)

    if not suggested_nixpkg then
        -- No mapping strategy found
        table.insert(verification_report.no_mapping, dep_name)
        return nil
    end

    -- Verify the suggested mapping exists in nixpkgs
    if verify_nixpkg_exists(suggested_nixpkg) then
        table.insert(verification_report.verified, {tool = dep_name, nixpkg = suggested_nixpkg})
        print(string.format("  ✓ %s → %s", dep_name, suggested_nixpkg))
        return suggested_nixpkg
    else
        table.insert(verification_report.failed_verification, {tool = dep_name, suggested = suggested_nixpkg})
        print(string.format("  ✗ %s → %s (not found in nixpkgs)", dep_name, suggested_nixpkg))
        return nil
    end
end

-- Main extraction function
local function extract_dependencies(lazyvim_path, mason_path, output_file)
    print("=== LazyVim Dependencies Extraction ===")
    print("LazyVim path: " .. lazyvim_path)
    print("Mason path: " .. (mason_path or "not provided"))
    print("Output file: " .. output_file)

    -- Extract core dependencies from health.lua
    print("\n=== Extracting core dependencies ===")
    local core_deps = extract_core_dependencies(lazyvim_path)

    -- Extract extra dependencies
    print("\n=== Extracting extra dependencies ===")
    local extra_deps = extract_extra_dependencies(lazyvim_path)

    -- Get all unique tools
    local all_tools = get_all_tools(core_deps, extra_deps)
    print(string.format("\nTotal unique tools found: %d", #all_tools))

    -- Get runtime dependencies if Mason path provided
    local runtime_deps = {}
    if mason_path then
        print("\n=== Extracting runtime dependencies from Mason ===")
        runtime_deps = get_runtime_dependencies(mason_path, all_tools)
        local runtime_count = 0
        for _ in pairs(runtime_deps) do runtime_count = runtime_count + 1 end
        print(string.format("Found runtime dependencies for %d tools", runtime_count))
    end

    -- Build dependencies structure with verified nixpkgs mappings
    print("\n=== Building dependencies structure with nixpkgs verification ===")

    -- Initialize verification report
    local verification_report = {
        verified = {},
        failed_verification = {},
        no_mapping = {}
    }

    local dependencies = {
        _comment = "LazyVim system dependencies with verified nixpkgs mappings - tools and their runtime_dependencies",
        generated = os.date("%Y-%m-%d %H:%M:%S"),
        lazyvim_path = lazyvim_path,
        mason_path = mason_path,

        core = {},
        extras = {},
    }

    -- Build core dependencies array with verified nixpkg mappings
    print("\nVerifying core dependencies:")
    for _, tool in ipairs(core_deps) do
        local nixpkg = resolve_and_verify_package(tool, verification_report)
        local entry = {name = tool}
        if nixpkg then
            entry.nixpkg = nixpkg
        end
        table.insert(dependencies.core, entry)
    end

    -- Process extras with verified mappings
    print("\nVerifying extra dependencies:")
    for extra_name, tools in pairs(extra_deps) do
        local extra_tools = {}

        for _, tool in ipairs(tools) do
            local nixpkg = resolve_and_verify_package(tool, verification_report)
            local entry = {name = tool}

            if nixpkg then
                entry.nixpkg = nixpkg
            end

            -- Add dependencies if they exist (verify each dependency)
            if runtime_deps[tool] then
                local deps = {}
                for _, dep_name in ipairs(runtime_deps[tool]) do
                    local dep_nixpkg = resolve_and_verify_package(dep_name, verification_report)
                    local dep_entry = {name = dep_name}
                    if dep_nixpkg then
                        dep_entry.nixpkg = dep_nixpkg
                    end
                    table.insert(deps, dep_entry)
                end
                if #deps > 0 then
                    entry.runtime_dependencies = deps
                end
            end

            table.insert(extra_tools, entry)
        end

        dependencies.extras[extra_name] = extra_tools
    end

    -- Write output file
    local function to_json(data, indent)
        -- Simple JSON serializer (reused from previous scripts)
        indent = indent or 0
        local spaces = string.rep("  ", indent)

        if type(data) == "table" then
            local is_array = true
            local max_index = 0
            for k, _ in pairs(data) do
                if type(k) ~= "number" then
                    is_array = false
                    break
                end
                max_index = math.max(max_index, k)
            end

            if is_array and max_index == #data and #data > 0 then
                local result = "[\n"
                for i, v in ipairs(data) do
                    result = result .. spaces .. "  " .. to_json(v, indent + 1)
                    if i < #data then result = result .. "," end
                    result = result .. "\n"
                end
                return result .. spaces .. "]"
            else
                local result = "{\n"
                local first = true
                local keys = {}
                for k in pairs(data) do table.insert(keys, k) end
                table.sort(keys)

                for _, k in ipairs(keys) do
                    local v = data[k]
                    if not first then result = result .. ",\n" end
                    first = false
                    result = result .. spaces .. '  "' .. k .. '": ' .. to_json(v, indent + 1)
                end

                if not first then result = result .. "\n" end
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

    local file = io.open(output_file, "w")
    if not file then
        error("Failed to open output file: " .. output_file)
    end

    file:write(to_json(dependencies))
    file:close()

    -- Deduplicate verification report entries
    local function deduplicate_list(list, key_field)
        local seen = {}
        local deduped = {}
        for _, item in ipairs(list) do
            local key = item[key_field]
            if not seen[key] then
                seen[key] = true
                table.insert(deduped, item)
            end
        end
        return deduped
    end

    local function deduplicate_strings(list)
        local seen = {}
        local deduped = {}
        for _, item in ipairs(list) do
            if not seen[item] then
                seen[item] = true
                table.insert(deduped, item)
            end
        end
        return deduped
    end

    -- Deduplicate verification results
    local verified_deduped = deduplicate_list(verification_report.verified, "tool")
    local failed_deduped = deduplicate_list(verification_report.failed_verification, "tool")
    local no_mapping_deduped = deduplicate_strings(verification_report.no_mapping)

    -- Generate verification report
    local report_file = output_file:gsub("%.json$", "-verification-report.json")
    local report = {
        _comment = "Nixpkgs package verification report for LazyVim dependencies",
        generated = os.date("%Y-%m-%d %H:%M:%S"),
        summary = {
            total_tools = #all_tools,
            verified_mappings = #verified_deduped,
            failed_verifications = #failed_deduped,
            no_mapping_strategy = #no_mapping_deduped,
            success_rate = string.format("%.1f%%", (#verified_deduped / #all_tools) * 100)
        },
        verified = verified_deduped,
        failed_verification = failed_deduped,
        no_mapping = no_mapping_deduped
    }

    local report_file_handle = io.open(report_file, "w")
    if report_file_handle then
        report_file_handle:write(to_json(report))
        report_file_handle:close()
    end

    -- Print summary
    print("\n=== Verification Summary ===")
    print(string.format("Total tools analyzed: %d", #all_tools))
    print(string.format("✓ Verified mappings: %d", #verified_deduped))
    print(string.format("✗ Failed verifications: %d", #failed_deduped))
    print(string.format("? No mapping strategy: %d", #no_mapping_deduped))
    print(string.format("Success rate: %.1f%%", (#verified_deduped / #all_tools) * 100))
    print(string.format("Dependencies written to: %s", output_file))
    print(string.format("Verification report: %s", report_file))
end

-- Command line interface
local function main()
    local lazyvim_path = arg[1]
    local mason_path = arg[2]  -- Optional
    local output_file = arg[3] or "data/dependencies.json"

    if not lazyvim_path then
        print("Usage: " .. arg[0] .. " <lazyvim_path> [mason_path] [output_file]")
        print("Example: " .. arg[0] .. " /tmp/lazyvim-temp /tmp/mason-registry data/dependencies.json")
        os.exit(1)
    end

    -- Verify LazyVim path exists
    local health_check = io.open(lazyvim_path .. "/lua/lazyvim/health.lua", "r")
    if not health_check then
        error("Invalid LazyVim path: " .. lazyvim_path .. " (health.lua not found)")
    end
    health_check:close()

    -- Verify Mason path if provided
    if mason_path then
        local mason_check = io.open(mason_path .. "/packages", "r")
        if not mason_check then
            print("Warning: Invalid Mason registry path: " .. mason_path .. " (packages directory not found)")
            mason_path = nil
        else
            io.close(mason_check)
        end
    end

    extract_dependencies(lazyvim_path, mason_path, output_file)
end

-- Run if called directly
if arg and arg[0] and arg[0]:match("extract%-dependencies") then
    main()
end

-- Export for testing
return {
    extract_core_dependencies = extract_core_dependencies,
    extract_extra_dependencies = extract_extra_dependencies,
    should_exclude_tool = should_exclude_tool,
    resolve_package_name = resolve_package_name
}