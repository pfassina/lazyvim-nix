{ pkgs, ... }:
let
  inherit (pkgs) lib;
  dev = import ../../nix/lib/dev-path.nix { inherit lib pkgs; pluginMappings = {}; };
  specs = [
    { name = "saghen/blink.cmp"; }
    { name = "rafamadriz/friendly-snippets"; dependencyOnly = true; }
    { name = "saghen/blink.compat"; dependencyOnly = true; }
  ];
  plugins = [ pkgs.vimPlugins.lazy-nvim pkgs.vimPlugins.friendly-snippets pkgs.vimPlugins.blink-compat ];
  path = dev.createDevPath specs plugins;
  fragments = dev.generateDevPluginSpecs dev specs plugins;
  check = pkgs.writeText "dependency-dev-specs.lua" ''
    vim.opt.rtp:prepend("${pkgs.vimPlugins.lazy-nvim}")
    local Config = require("lazy.core.config")
    Config.options = vim.tbl_deep_extend("force", Config.defaults, {
      root = vim.fn.stdpath("data") .. "/lazy",
      dev = { path = "${path}", fallback = false, patterns = {} },
    })
    local specs = {
      { "saghen/blink.cmp", dependencies = {
        "rafamadriz/friendly-snippets",
        { "saghen/blink.compat", optional = true },
      } },
      ${lib.concatStringsSep "\n" fragments}
    }
    local resolved = require("lazy.core.plugin").Spec.new(specs, { pkg = false })
    assert(#resolved.notifs == 0, vim.inspect(resolved.notifs))
    assert(resolved.plugins["blink.compat"] == nil, "optional dependency was activated by its dev fragment")
    local snippets = assert(resolved.plugins["friendly-snippets"])
    assert(snippets.dev and snippets.pin)
    assert(snippets.lazy == true, "dev fragment made a dependency eager")
    assert(vim.uv.fs_realpath(snippets.dir) == "${pkgs.vimPlugins.friendly-snippets}", "required dependency escaped the Nix store")
    print("Required dependencies use Nix; optional-only dependencies remain disabled")
  '';
in {
  test-dependency-dev-specs = pkgs.runCommand "test-dependency-dev-specs" {
    nativeBuildInputs = [ pkgs.neovim-unwrapped ];
  } ''
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
    export XDG_STATE_HOME="$HOME/state" XDG_CACHE_HOME="$HOME/cache"
    mkdir -p "$HOME"
    nvim --headless -u NONE -l ${check}
    touch "$out"
  '';
}
