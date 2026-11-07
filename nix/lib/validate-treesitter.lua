local site = assert(vim.env.LAZYVIM_TREESITTER_SITE)
local language = require("vim.treesitter.language")
local queries = require("vim.treesitter.query")
-- Do not let bundled queries or parsers hide errors in the installed site.
vim.opt.runtimepath = { site }

local errors = {}
local count = 0
for _, parser in ipairs(vim.fn.glob(site .. "/parser/*.so", false, true)) do
  local lang = vim.fn.fnamemodify(parser, ":t:r")
  local ok, loaded, err = pcall(language.add, lang, { path = parser })
  if not ok or not loaded then
    errors[#errors + 1] = lang .. "/parser: " .. tostring(ok and (err or loaded) or loaded)
  else
    count = count + 1
    for _, file in ipairs(vim.fn.glob(site .. "/queries/" .. lang .. "/*.scm", false, true)) do
      local query = vim.fn.fnamemodify(file, ":t:r")
      local query_ok, result = pcall(queries.get, lang, query)
      if not query_ok then
        errors[#errors + 1] = lang .. "/" .. query .. ": " .. tostring(result)
      end
    end
  end
end

if #errors > 0 then
  io.stderr:write("Treesitter validation failed:\n" .. table.concat(errors, "\n") .. "\n")
  vim.cmd("cquit 1")
end
print("Treesitter validation passed for " .. count .. " installed parsers")
vim.cmd("quit")
