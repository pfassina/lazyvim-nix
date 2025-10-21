#!/usr/bin/env lua

-- Script to extract treesitter parser requirements from LazyVim
-- Generates treesitter-mappings.json for use in module.nix

-- JSON encoder with pretty printing support
local function encode_json(obj, indent, current_indent)
  indent = indent or 0
  current_indent = current_indent or 0
  local spaces = string.rep("  ", current_indent)
  local next_spaces = string.rep("  ", current_indent + 1)

  if type(obj) == "table" then
    -- Check if it's an array (consecutive integer keys starting from 1)
    local is_array = true
    local count = 0
    for k, v in pairs(obj) do
      count = count + 1
      if type(k) ~= "number" or k ~= count then
        is_array = false
        break
      end
    end

    if is_array then
      -- Encode as JSON array
      if count == 0 then
        return "[]"
      end
      local items = {}
      for i = 1, count do
        table.insert(items, next_spaces .. encode_json(obj[i], indent, current_indent + 1))
      end
      return "[\n" .. table.concat(items, ",\n") .. "\n" .. spaces .. "]"
    else
      -- Encode as JSON object
      local items = {}
      -- Sort keys for consistent output
      local keys = {}
      for k in pairs(obj) do
        table.insert(keys, k)
      end
      table.sort(keys)

      for _, k in ipairs(keys) do
        local v = obj[k]
        local value_str = encode_json(v, indent, current_indent + 1)
        table.insert(items, next_spaces .. '"' .. k .. '": ' .. value_str)
      end

      if #items == 0 then
        return "{}"
      end
      return "{\n" .. table.concat(items, ",\n") .. "\n" .. spaces .. "}"
    end
  elseif type(obj) == "string" then
    return '"' .. obj .. '"'
  elseif type(obj) == "number" then
    return tostring(obj)
  elseif type(obj) == "boolean" then
    return obj and "true" or "false"
  else
    return "null"
  end
end

-- Get the LazyVim repo path from command line or use temp location
local lazyvim_repo = arg[1] or "/tmp/claude/lazyvim-repo"

if not lazyvim_repo then
  print("Usage: extract-treesitter.lua [lazyvim-repo-path]")
  os.exit(1)
end

-- Helper function to read file content
local function read_file(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil
  end
  local content = file:read("*all")
  file:close()
  return content
end

-- Helper function to extract parsers from ensure_installed
local function extract_parsers_from_content(content)
  local parsers = {}

  -- Find the nvim-treesitter plugin configuration block
  local treesitter_pattern = '"nvim%-treesitter/nvim%-treesitter"[^}]-}'
  local treesitter_block = content:match(treesitter_pattern)

  if not treesitter_block then
    return parsers
  end

  -- Pattern to find ensure_installed in the treesitter block specifically
  -- This handles both simple and function-based opts patterns
  local patterns = {
    -- Simple pattern: opts = { ensure_installed = { "parser1", "parser2" } }
    'opts%s*=%s*{[^}]*ensure_installed%s*=%s*{%s*([^}]-)%s*}',
    -- Function pattern: opts = function() ... ensure_installed = { ... } ... end
    'opts%s*=%s*function%(%).-ensure_installed%s*=%s*{%s*([^}]-)%s*}'
  }

  for _, pattern in ipairs(patterns) do
    local match = treesitter_block:match(pattern)
    if match then
      -- Extract individual parser names from quotes
      for parser in match:gmatch('"([^"]+)"') do
        table.insert(parsers, parser)
      end
      break -- Found parsers, no need to try other patterns
    end
  end

  return parsers
end

-- Extract core treesitter parsers from main treesitter configuration
local function extract_core_parsers()
  local treesitter_file = lazyvim_repo .. "/lua/lazyvim/plugins/treesitter.lua"
  local content = read_file(treesitter_file)

  if not content then
    error("Could not read treesitter.lua file: " .. treesitter_file)
  end

  local parsers = {}

  -- For the core treesitter file, use a simpler approach since it's in opts directly
  local pattern = 'ensure_installed%s*=%s*{%s*([^}]-)%s*}'
  local match = content:match(pattern)

  if match then
    -- Extract individual parser names from quotes
    for parser in match:gmatch('"([^"]+)"') do
      table.insert(parsers, parser)
    end
  end

  if #parsers == 0 then
    error("No core parsers found in treesitter.lua")
  end

  return parsers
end

-- Extract parsers from a specific language extra file
local function extract_extra_parsers(extra_file)
  local content = read_file(extra_file)
  if not content then
    return {}
  end

  -- Only process if the file contains nvim-treesitter configuration
  if not content:match('"nvim%-treesitter/nvim%-treesitter"') then
    return {}
  end

  return extract_parsers_from_content(content)
end

-- Extract parsers from all language extras
local function extract_all_extras()
  local extras_dir = lazyvim_repo .. "/lua/lazyvim/plugins/extras/lang"
  local extras = {}

  -- Get list of language extra files
  local handle = io.popen("ls " .. extras_dir .. "/*.lua 2>/dev/null")
  if not handle then
    error("Could not list extras directory: " .. extras_dir)
  end

  for file in handle:lines() do
    local name = file:match("([^/]+)%.lua$")
    if name then
      local parsers = extract_extra_parsers(file)
      if #parsers > 0 then
        -- Use "lang.{name}" format to match module structure
        extras["lang." .. name] = parsers
      end
    end
  end

  handle:close()
  return extras
end

-- Main extraction logic
local function main()
  print("Extracting treesitter parsers from LazyVim...")
  print("LazyVim repo: " .. lazyvim_repo)
  print("")

  -- Extract core parsers
  print("Extracting core parsers...")
  local core_parsers = extract_core_parsers()
  print("Found " .. #core_parsers .. " core parsers")

  -- Extract extra parsers
  print("Extracting extra parsers...")
  local extra_parsers = extract_all_extras()
  local extra_count = 0
  for _, parsers in pairs(extra_parsers) do
    extra_count = extra_count + #parsers
  end
  -- Count extra categories
  local extra_category_count = 0
  for _ in pairs(extra_parsers) do
    extra_category_count = extra_category_count + 1
  end

  print("Found " .. extra_count .. " extra parsers across " ..
        extra_category_count .. " language extras")

  -- Create the mappings structure
  local mappings = {
    core = core_parsers,
    extras = extra_parsers
  }

  -- Output as JSON
  local json_output = encode_json(mappings)
  print("")
  print("Generated treesitter mappings:")
  print(json_output)

  -- Write to file
  local output_file = "data/treesitter.json"
  local file = io.open(output_file, "w")
  if file then
    file:write(json_output)
    file:close()
    print("")
    print("✓ Wrote mappings to " .. output_file)
  else
    error("Could not write to " .. output_file)
  end
end

-- Run the extraction
main()