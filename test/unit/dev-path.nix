# Exercise repository identities with real lazy.nvim spec merging and dev paths.
{ pkgs, testLib, ... }:

let
  inherit (pkgs) lib;
  devPathLib = import ../../nix/lib/dev-path.nix {
    inherit lib pkgs;
    pluginMappings = {
      "nvim-mini/mini.ai" = { package = "mini-nvim"; module = "mini.ai"; };
      "nvim-mini/mini.pairs" = { package = "mini-nvim"; module = "mini.pairs"; };
    };
  };
  inherit (devPathLib) createDevPath getLinkName generateDevPluginSpecs;
  fakePlugin = name: pkgs.runCommand "fake-${name}" {} ''
    mkdir -p $out
    echo "${name}" > $out/marker
  '';
  fakeCatppuccin = fakePlugin "catppuccin";
  fakeOther = fakePlugin "other-nvim";
  fakeMini = fakePlugin "mini-nvim";
  specs = [
    { name = "catppuccin/nvim"; }
    { name = "other/nvim"; }
    { name = "nvim-mini/mini.ai"; }
    { name = "nvim-mini/mini.pairs"; }
    { name = "nvim-mini/mini.ai"; }
    { name = "owner/unresolved-plugin"; }
  ];
  resolved = [ fakeCatppuccin fakeOther fakeMini fakeMini fakeMini null ];
  devPath = createDevPath specs resolved;
  devSpecs = generateDevPluginSpecs devPathLib specs resolved;
  starterPatcher = import ../../nix/lib/starter-patcher.nix { inherit lib; };
  # Return the generated options so the test can normalize its own plugin specs.
  config = pkgs.writeText "dev-path-config.lua" (builtins.replaceStrings
    [ ''require("lazy").setup({'' "\n})" ] [ "return {" "\n}" ]
    (starterPatcher.patchStarterConfig {
    inherit devPath;
    availableDevSpecs = devSpecs;
    extrasImportSpecs = [];
    starterLua = builtins.readFile ../../data/starter-lazy.lua;
  }));
  behavior = pkgs.writeText "dev-path-behavior.lua" ''
    vim.opt.rtp:prepend("${pkgs.vimPlugins.lazy-nvim}")
    local config = dofile("${config}")
    local Config = require("lazy.core.config")
    Config.options = vim.tbl_deep_extend("force", Config.defaults, {
      root = vim.fn.stdpath("data") .. "/lazy",
      dev = config.dev,
    })
    local specs = {
      -- LazyVim's colorscheme spec uses a name unlike the repository basename.
      { "catppuccin/nvim", name = "catppuccin", opts = { flavour = "mocha" } },
      { "other/nvim", name = "other" },
      ${lib.concatStringsSep "\n      " devSpecs}
    }
    local Spec = require("lazy.core.plugin").Spec
    local spec = Spec.new(specs, { pkg = false })
    assert(#spec.notifs == 0, vim.inspect(spec.notifs))
    local plugins = spec.plugins
    assert(plugins.nvim == nil, "phantom basename-only nvim plugin")
    assert(plugins.catppuccin.dev and plugins.catppuccin.pin)
    assert(plugins.catppuccin.opts.flavour == "mocha", "renamed spec did not merge")
    assert(plugins.catppuccin.dir == "${devPath}/catppuccin--nvim")
    assert(vim.uv.fs_realpath(plugins.catppuccin.dir) == "${fakeCatppuccin}")
    -- A second repository with the same basename must retain its own package.
    assert(vim.uv.fs_realpath(config.dev.path({ url = "https://github.com/other/nvim.git", name = "renamed" })) == "${fakeOther}")
    assert(config.dev.path({ "catppuccin/nvim", name = "renamed" }) == plugins.catppuccin.dir)
    for _, module in ipairs({ "mini.ai", "mini.pairs" }) do
      assert(vim.uv.fs_realpath(plugins[module].dir) == "${fakeMini}")
      assert(vim.uv.fs_realpath("${devPath}/" .. module) == "${fakeMini}")
    end
    print("Renamed catppuccin merges by URL; repository dev paths and mini modules resolve Nix packages")
  '';
in {
  test-dev-link-name = testLib.testEval "dev-link-name"
    (getLinkName "catppuccin/nvim") "catppuccin--nvim";

  test-dev-path-creates-symlinks = testLib.runTest "dev-path-creates-symlinks"
    ''[ -L "${devPath}/catppuccin--nvim" ] && [ -L "${devPath}/other--nvim" ] && [ -L "${devPath}/mini.ai" ] && [ -L "${devPath}/mini.pairs" ]'';

  test-dev-path-links-point-to-plugins = testLib.runTest "dev-path-links-point-to-plugins"
    ''[ "$(readlink "${devPath}/catppuccin--nvim")" = "${fakeCatppuccin}" ] && [ "$(readlink "${devPath}/other--nvim")" = "${fakeOther}" ]'';

  # Four repository links plus two preserved module aliases; duplicates and
  # unresolved plugins must not add links.
  test-dev-path-dedup-and-null-filtering = testLib.runTest "dev-path-dedup-and-null-filtering"
    ''[ "$(ls "${devPath}" | wc -l)" -eq 6 ]'';

  test-dev-specs-format = testLib.testEval "dev-specs-format"
    (builtins.head devSpecs) ''{ "catppuccin/nvim", dev = true, pin = true },'';

  test-dev-specs-exclusions = testLib.testEval "dev-specs-exclusions"
    (builtins.length (generateDevPluginSpecs devPathLib [
      { name = "nvim-treesitter/nvim-treesitter"; }
      { name = "nvim-treesitter/nvim-treesitter-textobjects"; }
      { name = "owner/unresolved-plugin"; }
    ] [ fakeMini fakeMini null ])) 1;

  test-dev-path-lazy-identity = pkgs.runCommand "test-dev-path-lazy-identity" {
    nativeBuildInputs = [ pkgs.neovim-unwrapped ];
  } ''
    export HOME=$TMPDIR/home
    export XDG_CONFIG_HOME=$HOME/config XDG_DATA_HOME=$HOME/data
    export XDG_STATE_HOME=$HOME/state XDG_CACHE_HOME=$HOME/cache
    mkdir -p "$XDG_DATA_HOME/nvim/lazy"
    ln -s ${pkgs.vimPlugins.lazy-nvim} "$XDG_DATA_HOME/nvim/lazy/lazy.nvim"
    nvim --headless -u NONE -l ${behavior}
    touch $out
  '';
}
