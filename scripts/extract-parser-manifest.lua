-- Extract parser build metadata from nvim-treesitter's parsers.lua
-- Input: path to nvim-treesitter source (arg[1])
--        path to existing parser-manifest.json for caching (arg[2])
--        output file path (arg[3])
--        nvim-treesitter commit (arg[4])
-- Output: JSON file with parser name -> {url, revision, sha256, location?, requires?} mappings

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

local function sorted_keys(tbl)
    local keys = {}
    for key in pairs(tbl) do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

local function encode_json(value)
    local value_type = type(value)

    if value_type == "table" then
        local is_array = true
        local count = 0

        for key in pairs(value) do
            count = count + 1
            if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
                is_array = false
                break
            end
        end

        if is_array then
            for i = 1, count do
                if value[i] == nil then
                    is_array = false
                    break
                end
            end
        end

        if is_array then
            local items = {}
            for i = 1, count do
                table.insert(items, encode_json(value[i]))
            end
            return "[" .. table.concat(items, ",") .. "]"
        end

        local items = {}
        for _, key in ipairs(sorted_keys(value)) do
            table.insert(items, string.format("%q:%s", key, encode_json(value[key])))
        end
        return "{" .. table.concat(items, ",") .. "}"
    elseif value_type == "string" then
        return string.format("%q", value)
    elseif value_type == "number" or value_type == "boolean" then
        return tostring(value)
    elseif value == nil then
        return "null"
    else
        error("Unsupported JSON value type: " .. value_type)
    end
end

-- Parse nvim-treesitter's parsers.lua to extract parser specifications
local function extract_parsers_from_source(nvim_ts_path)
    local parsers_file = nvim_ts_path .. "/lua/nvim-treesitter/parsers.lua"
    local content = read_file(parsers_file)
    if not content then
        error("Could not read parsers.lua from: " .. parsers_file)
    end

    local env = {
        pairs = pairs,
        ipairs = ipairs,
        type = type,
        tostring = tostring,
        tonumber = tonumber,
        string = string,
        table = table,
        require = function()
            return {}
        end,
        vim = {
            fn = {
                has = function()
                    return 0
                end,
                stdpath = function()
                    return ""
                end,
                expand = function()
                    return ""
                end,
            },
            api = {},
            treesitter = {},
            validate = function()
            end,
            tbl_deep_extend = function(_, ...)
                local result = {}
                for i = 1, select("#", ...) do
                    local tbl = select(i, ...)
                    if type(tbl) == "table" then
                        for key, value in pairs(tbl) do
                            result[key] = value
                        end
                    end
                end
                return result
            end,
        },
    }

    local chunk, err = load(content, parsers_file, "t", env)
    if not chunk then
        error("Failed to parse parsers.lua: " .. tostring(err))
    end

    local ok, result = pcall(chunk)
    if not ok then
        error("Failed to execute parsers.lua: " .. tostring(result))
    end

    if type(result) ~= "table" then
        error("parsers.lua did not return a table")
    end

    return result
end

local function load_existing_manifest(path)
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

local function arrays_equal(a, b)
    if a == nil and b == nil then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

local function can_reuse_entry(existing, nvim_ts_commit, parser_name, expected_revision, expected_url, expected_location, expected_requires)
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
    return cached.revision == expected_revision
        and cached.url == expected_url
        and cached.location == expected_location
        and arrays_equal(cached.requires, expected_requires)
        and cached.sha256 ~= nil
end

local function prefetch_parser(url, revision)
    local quoted_url = string.format("%q", url)
    local quoted_revision = string.format("%q", revision)
    local cmd = string.format(
        "sh -c 'if command -v nix-prefetch-git >/dev/null 2>&1; then exec nix-prefetch-git --quiet --url %s --rev %s 2>/dev/null; else exec nix run --quiet nixpkgs#nix-prefetch-git -- --quiet --url %s --rev %s 2>/dev/null; fi'",
        quoted_url,
        quoted_revision,
        quoted_url,
        quoted_revision
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

local function main()
    local nvim_ts_path = arg[1]
    local existing_manifest_path = arg[2]
    local output_path = arg[3]
    local nvim_ts_commit = arg[4]

    if not nvim_ts_path or not output_path then
        print("Usage: extract-parser-manifest.lua <nvim-ts-path> <existing-manifest.json> <output.json> [nvim-ts-commit]")
        os.exit(1)
    end

    print("=== Extracting parser manifest from nvim-treesitter ===")
    print("    nvim-treesitter source: " .. nvim_ts_path)

    local parser_specs = extract_parsers_from_source(nvim_ts_path)
    local existing = load_existing_manifest(existing_manifest_path)
    if existing then
        print("    Loaded existing parser manifest for caching")
    end

    local result = {
        generated = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        nvim_treesitter_commit = nvim_ts_commit,
        parsers = {},
    }

    local prefetch_queue = {}
    local reusable_count = 0
    local skipped_count = 0

    for _, parser_name in ipairs(sorted_keys(parser_specs)) do
        local spec = parser_specs[parser_name]
        local info = spec and spec.install_info or nil
        local url = info and info.url or nil
        local revision = info and info.revision or nil
        local location = info and info.location or nil
        local requires = spec and spec.requires or nil

        if url and revision then
            if can_reuse_entry(existing, nvim_ts_commit, parser_name, revision, url, location, requires) then
                result.parsers[parser_name] = existing.parsers[parser_name]
                reusable_count = reusable_count + 1
            else
                table.insert(prefetch_queue, {
                    requires = requires,
                    location = location,
                    name = parser_name,
                    revision = revision,
                    url = url,
                })
            end
        else
            skipped_count = skipped_count + 1
        end
    end

    print(string.format("    Reusing %d cached parser entries", reusable_count))
    print(string.format("    Need to prefetch %d parsers", #prefetch_queue))
    print(string.format("    Skipping %d parsers without install metadata", skipped_count))

    if #prefetch_queue > 0 then
        print("=== Prefetching parser hashes ===")

        for i, task in ipairs(prefetch_queue) do
            print(string.format("    [%d/%d] Prefetching %s...", i, #prefetch_queue, task.name))

            local sha256, err = prefetch_parser(task.url, task.revision)
            if sha256 then
                result.parsers[task.name] = {
                    revision = task.revision,
                    sha256 = sha256,
                    url = task.url,
                }
                if task.location ~= nil then
                    result.parsers[task.name].location = task.location
                end
                if task.requires ~= nil and #task.requires > 0 then
                    result.parsers[task.name].requires = task.requires
                end
            else
                error(string.format("Failed to prefetch parser '%s': %s", task.name, err or "unknown error"))
            end
        end
    end

    local parser_count = 0
    for _ in pairs(result.parsers) do
        parser_count = parser_count + 1
    end

    print("=== Parser manifest extraction complete ===")
    print(string.format("    Generated %d parser entries", parser_count))

    write_file(output_path, encode_json(result) .. "\n")
    print("    Written to: " .. output_path)
end

main()
