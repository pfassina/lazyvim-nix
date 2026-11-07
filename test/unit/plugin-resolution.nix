# Unit tests for plugin name resolution and plugin building
# These tests import the real implementation from nix/lib/ and verify its
# behavior - they intentionally do not re-implement any module logic.
{ pkgs, testLib, ... }:

let
  inherit (pkgs) lib;

  # Fixture mappings exercising both mapping shapes (string and multi-module)
  fixtureMappings = {
    "L3MON4D3/LuaSnip" = "luasnip";
    "catppuccin/nvim" = "catppuccin-nvim";
    "nvim-mini/mini.ai" = { package = "mini-nvim"; module = "mini.ai"; };
    "nvim-mini/mini.pairs" = { package = "mini-nvim"; module = "mini.pairs"; };
    "folke/lazy.nvim" = "lazy-nvim";
  };

  # The real plugin resolution library under test
  pluginLib = import ../../nix/lib/plugin-resolution.nix {
    inherit lib pkgs;
    pluginMappings = fixtureMappings;
    ignoreBuildNotifications = true;
  };

  inherit (pluginLib) resolvePluginName resolvePlugin buildVimPluginFromSource;

  # Real shipped mappings, to validate their structure
  realMappings = builtins.fromJSON (builtins.readFile ../../data/mappings.json);

in {
  # resolvePluginName: manual mappings take precedence
  test-resolve-manual-string-mapping = testLib.testEval
    "resolve-manual-string-mapping"
    (resolvePluginName "L3MON4D3/LuaSnip")
    "luasnip";

  test-resolve-manual-mapping-overrides-automatic = testLib.testEval
    "resolve-manual-mapping-overrides-automatic"
    (resolvePluginName "catppuccin/nvim")
    "catppuccin-nvim";

  test-resolve-multi-module-mapping = testLib.testEval
    "resolve-multi-module-mapping"
    (resolvePluginName "nvim-mini/mini.ai")
    "mini-nvim";

  # resolvePluginName: automatic resolution patterns for unmapped plugins
  test-resolve-nvim-suffix-with-dot = testLib.testEval
    "resolve-nvim-suffix-with-dot"
    (resolvePluginName "folke/tokyonight.nvim")
    "tokyonight-nvim";

  test-resolve-nvim-suffix-with-dash = testLib.testEval
    "resolve-nvim-suffix-with-dash"
    (resolvePluginName "owner/telescope-nvim")
    "telescope-nvim";

  test-resolve-nvim-prefix = testLib.testEval
    "resolve-nvim-prefix"
    (resolvePluginName "hrsh7th/nvim-cmp")
    "nvim-cmp";

  test-resolve-fallback-dashes-to-underscores = testLib.testEval
    "resolve-fallback-dashes-to-underscores"
    (resolvePluginName "owner/some-plugin")
    "some_plugin";

  test-resolve-name-without-owner = testLib.testEval
    "resolve-name-without-owner"
    (resolvePluginName "single-plugin")
    "single_plugin";

  test-resolve-empty-name = testLib.testEval
    "resolve-empty-name"
    (resolvePluginName "")
    "";

  # resolvePlugin: strategy and fallback behavior
  test-resolve-plugin-from-nixpkgs = testLib.testEval
    "resolve-plugin-from-nixpkgs"
    (resolvePlugin { pluginSource = "nixpkgs"; } {
      name = "folke/lazy.nvim";
      version_info = { };
    }).pname
    pkgs.vimPlugins.lazy-nvim.pname;

  # nixpkgs strategy + unpinned "*" should use the nixpkgs package, not source-build the tag
  test-resolve-plugin-nixpkgs-wildcard-uses-nixpkgs = testLib.testEval
    "resolve-plugin-nixpkgs-wildcard-uses-nixpkgs"
    (resolvePlugin { pluginSource = "nixpkgs"; } {
      name = "folke/lazy.nvim";
      version_info = {
        lazyvim_version = "*";
        tag = "v99.99.99";  # mocks extract-plugins.lua's latest upstream release, not a pin
        sha256 = lib.fakeSha256;
      };
    }).version
    pkgs.vimPlugins.lazy-nvim.version;

  test-resolve-plugin-unresolvable-returns-null = testLib.testEval
    "resolve-plugin-unresolvable-returns-null"
    (resolvePlugin { pluginSource = "nixpkgs"; } {
      name = "nonexistent/totally-fake-plugin-xyz";
      version_info = { };
    } == null)
    true;

  # When the target version is not in nixpkgs and no sha256 is available for
  # a source build, resolution falls back to the nixpkgs package
  test-resolve-plugin-falls-back-to-nixpkgs-without-sha256 = testLib.testEval
    "resolve-plugin-falls-back-to-nixpkgs-without-sha256"
    (resolvePlugin { pluginSource = "latest"; } {
      name = "folke/lazy.nvim";
      version_info = { tag = "v99.99.99"; sha256 = null; };
    }).pname
    pkgs.vimPlugins.lazy-nvim.pname;

  test-resolve-plugin-branch-requires-source-build = testLib.testEval
    "resolve-plugin-branch-requires-source-build"
    (resolvePlugin { pluginSource = "latest"; } {
      name = "folke/tokyonight.nvim";
      version_info = {
        lazyvim_version = "main";
        lazyvim_version_type = "branch";
        sha256 = lib.fakeSha256;
      };
    }).version
    "main";

  # buildVimPluginFromSource: version selection priority
  test-build-from-source-tag-beats-commit = testLib.testEval
    "build-from-source-tag-beats-commit"
    (buildVimPluginFromSource {
      name = "folke/tokyonight.nvim";
      version_info = {
        tag = "v1.2.3";
        commit = "abc1234";
        sha256 = lib.fakeSha256;
      };
    }).version
    "v1.2.3";

  test-build-from-source-lazyvim-version-beats-tag = testLib.testEval
    "build-from-source-lazyvim-version-beats-tag"
    (buildVimPluginFromSource {
      name = "folke/tokyonight.nvim";
      version_info = {
        lazyvim_version = "v2.0.0";
        tag = "v1.0.0";
        sha256 = lib.fakeSha256;
      };
    }).version
    "v2.0.0";

  test-build-from-source-latest-version-beats-commit = testLib.testEval
    "build-from-source-latest-version-beats-commit"
    (buildVimPluginFromSource {
      name = "folke/tokyonight.nvim";
      version_info = {
        latest_version = "v3.0.0";
        commit = "abc1234";
        sha256 = lib.fakeSha256;
      };
    }).version
    "v3.0.0";

  # Plugins hosted outside GitHub (e.g. Codeberg) are fetched from source_url
  test-build-from-source-uses-source-url = testLib.testEval
    "build-from-source-uses-source-url"
    (buildVimPluginFromSource {
      name = "owner/some-plugin";
      source_url = "https://codeberg.org/owner/some-plugin";
      version_info = {
        tag = "v1.0.0";
        sha256 = lib.fakeSha256;
      };
    }).meta.homepage
    "https://codeberg.org/owner/some-plugin";

  test-build-from-source-pname-is-repo = testLib.testEval
    "build-from-source-pname-is-repo"
    (buildVimPluginFromSource {
      name = "folke/tokyonight.nvim";
      version_info = {
        tag = "v1.2.3";
        sha256 = lib.fakeSha256;
      };
    }).pname
    "tokyonight.nvim";

  # Shipped data/mappings.json: every mapping is a string or { package, module }
  test-real-mappings-structure-valid = testLib.testEval
    "real-mappings-structure-valid"
    (builtins.all (mapping:
      builtins.isString mapping ||
      (builtins.isAttrs mapping && mapping ? package && mapping ? module)
    ) (builtins.attrValues realMappings))
    true;
}
