-- Extract parser revisions from nvim-treesitter's parsers.lua
-- Input: path to nvim-treesitter source (arg[1])
--        path to treesitter.json with core/extras parsers (arg[2])
--        path to existing parser-revisions.json for caching (arg[3])
--        output file path (arg[4])
-- Output: JSON file with parser name -> {url, revision, sha256} mappings

local function read_file(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*all")
    file:close()
    return content
end

local function write_file(path, content)
    local file = io.open(path, "w")
    if not file then
        error("Failed to write file: " .. path)
    end
    file:write(content)
    file:close()
end

-- Parse nvim-treesitter's parsers.lua to extract parser specifications
local function extract_parsers_from_source(nvim_ts_path)
    local parsers_file = nvim_ts_path .. "/lua/nvim-treesitter/parsers.lua"
    local content = read_file(parsers_file)
    if not content then
        error("Could not read parsers.lua from: " .. parsers_file)
    end

    -- Create minimal environment for loading parsers.lua
    local env = {
        pairs = pairs,
        ipairs = ipairs,
        type = type,
        tostring = tostring,
        tonumber = tonumber,
        string = string,
        table = table,
        require = function() return {} end,
        vim = {
            fn = {
                has = function() return 0 end,
                stdpath = function() return "" end,
                expand = function() return "" end,
            },
            api = {},
            treesitter = {},
            validate = function() end,
            tbl_deep_extend = function(mode, ...)
                local result = {}
                for i = 1, select("#", ...) do
                    local t = select(i, ...)
                    if type(t) == "table" then
                        for k, v in pairs(t) do
                            result[k] = v
                        end
                    end
                end
                return result
            end,
        },
    }

    -- Load and execute parsers.lua
    local chunk, err = load(content, parsers_file, "t", env)
    if not chunk then
        error("Failed to parse parsers.lua: " .. tostring(err))
    end

    local ok, result = pcall(chunk)
    if not ok then
        error("Failed to execute parsers.lua: " .. tostring(result))
    end

    -- The file returns a table of parsers
    if type(result) ~= "table" then
        error("parsers.lua did not return a table")
    end

    return result
end

-- Load treesitter.json to get list of needed parsers
local function load_needed_parsers(treesitter_json_path)
    local content = read_file(treesitter_json_path)
    if not content then
        error("Could not read treesitter.json from: " .. treesitter_json_path)
    end

    local ok, data = pcall(vim.json.decode, content)
    if not ok then
        error("Failed to parse treesitter.json: " .. tostring(data))
    end

    -- Collect all unique parser names from core and extras
    local parsers = {}
    local seen = {}

    -- Add core parsers
    if data.core then
        for _, parser in ipairs(data.core) do
            if not seen[parser] then
                seen[parser] = true
                table.insert(parsers, parser)
            end
        end
    end

    -- Add parsers from all extras
    if data.extras then
        for _, extra_parsers in pairs(data.extras) do
            if type(extra_parsers) == "table" then
                for _, parser in ipairs(extra_parsers) do
                    if not seen[parser] then
                        seen[parser] = true
                        table.insert(parsers, parser)
                    end
                end
            end
        end
    end

    table.sort(parsers)
    return parsers
end

-- Load existing parser revisions for caching
local function load_existing_revisions(path)
    local content = read_file(path)
    if not content then
        return nil
    end

    local ok, data = pcall(vim.json.decode, content)
    if not ok then
        return nil
    end

    return data
end

-- Check if existing revision can be reused
local function can_reuse_revision(existing, nvim_ts_commit, parser_name, expected_revision)
    if not existing then
        return false
    end
    if existing.nvim_treesitter_commit ~= nvim_ts_commit then
        return false
    end
    if not existing.parsers or not existing.parsers[parser_name] then
        return false
    end
    local cached = existing.parsers[parser_name]
    return cached.revision == expected_revision and cached.sha256 ~= nil
end

-- Prefetch a git repository and return its SHA256
local function prefetch_parser(url, revision)
    local cmd = string.format(
        "nix-prefetch-git --quiet --url '%s' --rev '%s' 2>/dev/null",
        url, revision
    )

    local handle = io.popen(cmd)
    if not handle then
        return nil, "Failed to run nix-prefetch-git"
    end

    local output = handle:read("*all")
    local success = handle:close()

    if not success then
        return nil, "nix-prefetch-git failed"
    end

    local ok, data = pcall(vim.json.decode, output)
    if not ok or not data or not data.sha256 then
        return nil, "Failed to parse nix-prefetch-git output"
    end

    return data.sha256
end

-- Get nvim-treesitter commit from plugins.json
local function get_nvim_treesitter_commit(plugins_json_path)
    local content = read_file(plugins_json_path)
    if not content then
        return nil
    end

    local ok, data = pcall(vim.json.decode, content)
    if not ok or not data.plugins then
        return nil
    end

    for _, plugin in ipairs(data.plugins) do
        if plugin.name == "nvim-treesitter/nvim-treesitter" then
            return plugin.version_info and plugin.version_info.commit
        end
    end

    return nil
end

local function main()
    local nvim_ts_path = arg[1]
    local treesitter_json_path = arg[2]
    local existing_revisions_path = arg[3]
    local output_path = arg[4]
    local nvim_ts_commit = arg[5]

    if not nvim_ts_path or not treesitter_json_path or not output_path then
        print("Usage: extract-parser-revisions.lua <nvim-ts-path> <treesitter.json> <existing-revisions.json> <output.json> [nvim-ts-commit]")
        os.exit(1)
    end

    print("=== Extracting parser revisions from nvim-treesitter ===")
    print("    nvim-treesitter source: " .. nvim_ts_path)

    -- Load parser specifications from nvim-treesitter
    local parser_specs = extract_parsers_from_source(nvim_ts_path)

    -- Load list of needed parsers
    local needed_parsers = load_needed_parsers(treesitter_json_path)
    print(string.format("    Found %d needed parsers", #needed_parsers))

    -- Load existing revisions for caching
    local existing = load_existing_revisions(existing_revisions_path)
    if existing then
        print("    Loaded existing parser revisions for caching")
    end

    -- Build result
    local result = {
        nvim_treesitter_commit = nvim_ts_commit,
        generated = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        parsers = {},
    }

    local prefetch_queue = {}
    local reused_count = 0
    local missing_count = 0

    -- First pass: identify what needs to be fetched
    for _, parser_name in ipairs(needed_parsers) do
        local spec = parser_specs[parser_name]
        if spec and spec.install_info then
            local info = spec.install_info
            local url = info.url
            local revision = info.revision

            if url and revision then
                if can_reuse_revision(existing, nvim_ts_commit, parser_name, revision) then
                    -- Reuse cached result
                    result.parsers[parser_name] = existing.parsers[parser_name]
                    reused_count = reused_count + 1
                else
                    -- Queue for prefetch
                    table.insert(prefetch_queue, {
                        name = parser_name,
                        url = url,
                        revision = revision,
                        location = info.location,
                    })
                end
            else
                print(string.format("    Warning: Parser '%s' missing url or revision", parser_name))
                missing_count = missing_count + 1
            end
        else
            print(string.format("    Warning: Parser '%s' not found in nvim-treesitter", parser_name))
            missing_count = missing_count + 1
        end
    end

    print(string.format("    Reusing %d cached revisions", reused_count))
    print(string.format("    Need to prefetch %d parsers", #prefetch_queue))

    if missing_count > 0 then
        print(string.format("    Missing %d parsers (will use nixpkgs fallback)", missing_count))
    end

    -- Prefetch parsers that need it
    if #prefetch_queue > 0 then
        print("=== Prefetching parser hashes ===")

        for i, task in ipairs(prefetch_queue) do
            print(string.format("    [%d/%d] Prefetching %s...", i, #prefetch_queue, task.name))

            local sha256, err = prefetch_parser(task.url, task.revision)
            if sha256 then
                result.parsers[task.name] = {
                    url = task.url,
                    revision = task.revision,
                    sha256 = sha256,
                }
                if task.location then
                    result.parsers[task.name].location = task.location
                end
            else
                print(string.format("      Error: %s (will use nixpkgs fallback)", err or "unknown"))
            end
        end
    end

    -- Count results
    local success_count = 0
    for _ in pairs(result.parsers) do
        success_count = success_count + 1
    end

    print(string.format("=== Parser extraction complete ==="))
    print(string.format("    Successfully extracted: %d parsers", success_count))
    print(string.format("    Missing (will use nixpkgs): %d parsers", #needed_parsers - success_count))

    -- Write output as JSON
    local json_output = vim.json.encode(result)
    -- Pretty print the JSON
    local pretty_json = json_output:gsub('","', '",\n    "'):gsub('{"', '{\n  "'):gsub('"}', '"\n}'):gsub('"parsers":{', '"parsers": {\n    ')
    write_file(output_path, pretty_json .. "\n")

    print("    Written to: " .. output_path)
end

main()
