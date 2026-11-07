local lazyvim, lazy, input, output = unpack(arg)
local settings = vim.json.decode(table.concat(vim.fn.readfile(input), "\n"))
vim.opt.runtimepath:prepend(lazy)
vim.opt.runtimepath:prepend(lazyvim)
if settings.config and settings.config ~= vim.NIL then
  vim.opt.runtimepath:prepend(settings.config)
  package.path = settings.config .. "/?.lua;" .. settings.config .. "/lua/?.lua;" .. package.path
end
local config = require("lazyvim.config")
local lazy_config = require("lazy.core.config")
lazy_config.options = vim.deepcopy(lazy_config.defaults)
-- Normalize the real specs, including merged and nested dependencies. This runs
-- LazyVim's options lifecycle and default selection, but never installs plugins
-- or runs their init/config functions.
local specs = { { "LazyVim/LazyVim", dir = lazyvim, import = "lazyvim.plugins" } }
vim.list_extend(specs, settings.imports)
lazy_config.options.spec = specs
lazy_config.spec = require("lazy.core.plugin").Spec.new(nil, { pkg = false })
lazy_config.spec:parse(specs)
assert(#lazy_config.spec.notifs == 0, vim.inspect(lazy_config.spec.notifs))
local enabled, disabled, plugins = {}, {}, {}
for _, extra in pairs(config.get_defaults()) do
  local list = extra.enabled and enabled or disabled
  list[#list + 1] = extra.extra
end
for _, plugin in pairs(lazy_config.spec.plugins) do
  local repo = plugin.url and plugin.url:match("github.com[/:](.+)")
  if repo then
    plugins[#plugins + 1] = repo:gsub("%.git$", "")
  end
end
table.sort(enabled)
table.sort(disabled)
table.sort(plugins)
vim.fn.writefile({ vim.json.encode({ enabled = enabled, disabled = disabled, plugins = plugins }) }, output)
