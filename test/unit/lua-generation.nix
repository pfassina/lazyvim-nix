# Unit tests for the public Lua-generation helpers (the flake's `lib` output).
# These import and call the real implementation in nix/lib/lua-generation.nix.
{ pkgs, testLib, ... }:

let
  inherit (pkgs) lib;

  # The real library under test, imported exactly as flake.nix does
  luaGen = import ../../nix/lib/lua-generation.nix { inherit lib; };
  inherit (luaGen) lazyPlugin lazyConfig;
in
{
  test-lua-gen-single-spec-with-plugin = testLib.testEval
    "lua-gen-single-spec-with-plugin"
    (lazyConfig {
      plugin = "folke/tokyonight.nvim";
      opts = { style = "night"; transparent = true; };
    })
    ''
      return {
        "folke/tokyonight.nvim",
        ["opts"] = {
          ["style"] = "night",
          ["transparent"] = true
        }
      }'';

  # A spec with only `plugin` must not glue the closing brace to the comma
  test-lua-gen-plugin-only = testLib.testEval
    "lua-gen-plugin-only"
    (lazyConfig { plugin = "folke/noice.nvim"; })
    ''return { "folke/noice.nvim" }'';

  # Without `plugin`, the spec is a plain keyed table (e.g. local dir plugins)
  test-lua-gen-spec-without-plugin = testLib.testEval
    "lua-gen-spec-without-plugin"
    (lazyConfig { dir = "/some/path"; name = "local-plugin"; })
    ''
      return {
        ["dir"] = "/some/path",
        ["name"] = "local-plugin"
      }'';

  test-lua-gen-list-of-specs = testLib.testEval
    "lua-gen-list-of-specs"
    (lazyConfig [
      { plugin = "Lazyvim/Lazyvim"; opts.colorscheme = "catppuccin"; }
      { plugin = "neovim/nvim-lspconfig"; opts.servers.nixd = { }; }
    ])
    ''
      return {
        ({
          "Lazyvim/Lazyvim",
          ["opts"] = {
            ["colorscheme"] = "catppuccin"
          }
        }),
        ({
          "neovim/nvim-lspconfig",
          ["opts"] = {
            ["servers"] = {
              ["nixd"] = {}
            }
          }
        })
      }'';

  test-lua-gen-nested-opts = testLib.testEval
    "lua-gen-nested-opts"
    (lazyConfig {
      plugin = "neovim/nvim-lspconfig";
      opts = { servers = [ 1 2 ]; enabled = false; count = 3; };
    })
    ''
      return {
        "neovim/nvim-lspconfig",
        ["opts"] = {
          ["count"] = 3,
          ["enabled"] = false,
          ["servers"] = {
            1,
            2
          }
        }
      }'';

  # mkLuaInline values are emitted as raw Lua, not quoted strings
  test-lua-gen-mkluainline-passthrough = testLib.testEval
    "lua-gen-mkluainline-passthrough"
    (lazyConfig {
      plugin = "folke/noice.nvim";
      opts = lib.generators.mkLuaInline "function(_, opts) opts.x = 1 end";
    })
    ''
      return {
        "folke/noice.nvim",
        ["opts"] = (function(_, opts) opts.x = 1 end)
      }'';

  test-lua-gen-empty-attrset = testLib.testEval
    "lua-gen-empty-attrset"
    (lazyConfig { })
    "return {}";

  test-lua-gen-empty-list = testLib.testEval
    "lua-gen-empty-list"
    (lazyConfig [ ])
    "return {}";

  # The plugin name is escaped like every other string
  test-lua-gen-escapes-plugin-name = testLib.testEval
    "lua-gen-escapes-plugin-name"
    (lazyConfig {
      plugin = "weird\"name\\test";
      lazy = false;
    })
    ''
      return {
        "weird\"name\\test",
        ["lazy"] = false
      }'';

  test-lua-gen-escapes-string-values = testLib.testEval
    "lua-gen-escapes-string-values"
    (lazyConfig {
      plugin = "a/b";
      opts.desc = "has \"quotes\" and \\backslash";
    })
    ''
      return {
        "a/b",
        ["opts"] = {
          ["desc"] = "has \"quotes\" and \\backslash"
        }
      }'';

  # lazyPlugin renders a bare spec table without the `return` prefix
  test-lua-gen-lazyplugin-bare = testLib.testEval
    "lua-gen-lazyplugin-bare"
    (lazyPlugin { plugin = "a/b"; lazy = false; })
    ''
      {
        "a/b",
        ["lazy"] = false
      }'';
}
