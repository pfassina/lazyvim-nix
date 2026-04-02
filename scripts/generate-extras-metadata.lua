#!/usr/bin/env -S nvim --headless -l

-- Generate extras metadata from LazyVim repository
-- This script scans the LazyVim extras directory and creates extras.json

local function main()
  local temp_dir = vim.fn.tempname()
  vim.fn.mkdir(temp_dir, "p")

  print("Cloning LazyVim repository...")
  vim.fn.system({
    "git", "clone", "--depth", "1", "--filter=blob:none", "--sparse",
    "https://github.com/LazyVim/LazyVim", temp_dir .. "/LazyVim"
  })

  vim.fn.system({
    "git", "-C", temp_dir .. "/LazyVim", "sparse-checkout", "set", "lua/lazyvim/plugins/extras"
  })

  local extras_dir = temp_dir .. "/LazyVim/lua/lazyvim/plugins/extras"

  -- Check if directory exists
  if vim.fn.isdirectory(extras_dir) == 0 then
    print("Error: Extras directory not found")
    vim.fn.delete(temp_dir, "rf")
    vim.cmd("quit 1")
    return
  end

  print("Generating extras metadata...")

  local extras_data = {}
  local total_count = 0

  -- Get all category directories and sort them
  local categories = vim.fn.glob(extras_dir .. "/*", false, true)
  table.sort(categories)

  for _, category_path in ipairs(categories) do
    local category = vim.fn.fnamemodify(category_path, ":t")

    -- Only process directories (skip any files in the root like vscode.lua)
    if vim.fn.isdirectory(category_path) == 1 then
      extras_data[category] = {}

      -- Get all Lua files in this category and sort them
      local lua_files = vim.fn.glob(category_path .. "/*.lua", false, true)
      table.sort(lua_files)

      for _, lua_file in ipairs(lua_files) do
        local extra_name = vim.fn.fnamemodify(lua_file, ":t:r")  -- Remove path and .lua extension
        -- Convert hyphens to underscores for keys (matching Nix attribute names)
        local key_name = extra_name:gsub("-", "_")

        extras_data[category][key_name] = {
          name = extra_name,
          category = category,
          import = string.format("lazyvim.plugins.extras.%s.%s", category, extra_name)
        }
        total_count = total_count + 1
      end

      -- Handle subdirectory extras (e.g., lang/typescript/ with init.lua)
      local subdirs = vim.fn.glob(category_path .. "/*", false, true)
      table.sort(subdirs)

      for _, subdir in ipairs(subdirs) do
        if vim.fn.isdirectory(subdir) == 1 then
          local init_file = subdir .. "/init.lua"
          if vim.fn.filereadable(init_file) == 1 then
            local extra_name = vim.fn.fnamemodify(subdir, ":t")
            local key_name = extra_name:gsub("-", "_")

            extras_data[category][key_name] = {
              name = extra_name,
              category = category,
              import = string.format("lazyvim.plugins.extras.%s.%s", category, extra_name)
            }
            total_count = total_count + 1
          end
        end
      end
    end
  end

  -- Get the script directory and project root
  local script_path = debug.getinfo(1).source:match("@?(.*)")
  local script_dir = vim.fn.fnamemodify(script_path, ":h")
  local project_root = vim.fn.fnamemodify(script_dir, ":h")
  local output_file = project_root .. "/data/extras.json"

  -- Ensure data directory exists
  vim.fn.mkdir(project_root .. "/data", "p")

  -- Write formatted JSON to file
  local json_string = vim.fn.json_encode(extras_data)
  -- Format the JSON for readability and sort keys
  local formatted = vim.fn.system({ "jq", "-S", "." }, json_string)

  vim.fn.writefile(vim.fn.split(formatted, "\n"), output_file)

  -- Clean up
  vim.fn.delete(temp_dir, "rf")

  print("Extras metadata generated at " .. output_file)
  print("Total extras found: " .. total_count)

  os.exit(0)
end

-- Run main function
main()