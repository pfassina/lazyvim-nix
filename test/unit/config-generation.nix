# Unit tests for configuration generation
# Imports the real nix/lib/config-generation.nix (and, through it, the
# starter patcher) and verifies the generated lazy.nvim configuration.
{ pkgs, testLib, moduleUnderTest }:

let
  lib = pkgs.lib;

  # The real libraries under test
  configLib = import ../../nix/lib/config-generation.nix { inherit lib; };
  dataLib = import ../../nix/lib/data-loading.nix { inherit lib pkgs; };

  inherit (configLib) extrasImportSpecs extrasConfigFiles lazyConfig;
  inherit (dataLib) starterLua starterVersion;

  sampleExtras = [
    {
      name = "rust";
      category = "lang";
      import = "lazyvim.plugins.extras.lang.rust";
      hasConfig = false;
      config = "";
    }
    {
      name = "go";
      category = "lang";
      import = "lazyvim.plugins.extras.lang.go";
      hasConfig = true;
      config = "return { custom = true }";
    }
  ];

  # Generate a full lazy.nvim config from the real shipped starter
  patchedConfig = lazyConfig {
    inherit starterLua starterVersion;
    devPath = "/nix/store/fake-dev-path";
    extrasImportSpecs = extrasImportSpecs sampleExtras;
    availableDevSpecs = [ ''{ "lazy.nvim", dev = true, pin = true },'' ];
  };

  generatedConfigFiles = extrasConfigFiles sampleExtras "nvim";

in {
  # extrasImportSpecs: one lazy.nvim import line per extra
  test-extras-import-specs-format = testLib.testEval
    "extras-import-specs-format"
    (extrasImportSpecs sampleExtras == [
      ''{ import = "lazyvim.plugins.extras.lang.rust" },''
      ''{ import = "lazyvim.plugins.extras.lang.go" },''
    ])
    true;

  # extrasConfigFiles: only extras with hasConfig produce override files
  test-extras-config-files-only-with-config = testLib.testEval
    "extras-config-files-only-with-config"
    (builtins.attrNames generatedConfigFiles)
    [ "nvim/lua/plugins/extras-lang-go.lua" ];

  # extrasConfigFiles: the user's config override ends up in the file body
  test-extras-config-files-content = testLib.testEval
    "extras-config-files-content"
    (lib.hasInfix "return { custom = true }"
      generatedConfigFiles."nvim/lua/plugins/extras-lang-go.lua".text)
    true;

  # lazyConfig: extras imports are injected into the spec
  test-lazy-config-injects-extras = testLib.testEval
    "lazy-config-injects-extras"
    (lib.hasInfix ''{ import = "lazyvim.plugins.extras.lang.rust" },'' patchedConfig)
    true;

  # lazyConfig: the Nix dev path is wired into lazy.nvim's dev settings
  test-lazy-config-sets-dev-path = testLib.testEval
    "lazy-config-sets-dev-path"
    (lib.hasInfix ''path = "/nix/store/fake-dev-path",'' patchedConfig)
    true;

  # lazyConfig: dev specs for Nix-managed plugins are included
  test-lazy-config-includes-dev-specs = testLib.testEval
    "lazy-config-includes-dev-specs"
    (lib.hasInfix ''{ "lazy.nvim", dev = true, pin = true },'' patchedConfig)
    true;

  # lazyConfig: Mason is disabled since Nix provides the tools
  test-lazy-config-disables-mason = testLib.testEval
    "lazy-config-disables-mason"
    (lib.hasInfix ''{ "mason-org/mason.nvim", enabled = false },'' patchedConfig &&
     lib.hasInfix ''{ "mason-org/mason-lspconfig.nvim", enabled = false },'' patchedConfig)
    true;

  # lazyConfig: the update checker is disabled (Nix manages versions)
  test-lazy-config-disables-checker = testLib.testEval
    "lazy-config-disables-checker"
    (lib.hasInfix "enabled = false, -- [NIX] Disabled" patchedConfig &&
     !(lib.hasInfix "enabled = true, -- check for plugin updates periodically" patchedConfig))
    true;

  # lazyConfig: the upstream spec section was actually replaced
  test-lazy-config-replaces-upstream-spec = testLib.testEval
    "lazy-config-replaces-upstream-spec"
    (lib.hasInfix "-- add LazyVim and import its plugins" patchedConfig)
    false;

  # lazyConfig: the starter version is recorded in the header
  test-lazy-config-records-starter-version = testLib.testEval
    "lazy-config-records-starter-version"
    (lib.hasInfix "(commit: ${starterVersion})" patchedConfig)
    true;

  # lazyConfig: a starter whose spec section drifted from the expected
  # upstream structure fails loudly instead of silently producing an
  # unpatched config
  test-lazy-config-throws-on-unpatchable-starter = testLib.testEval
    "lazy-config-throws-on-unpatchable-starter"
    (builtins.tryEval (lazyConfig {
      starterLua = ''
        spec = {
          -- add LazyVim and import its plugins
          { "LazyVim/LazyVim", import = "lazyvim.plugins", restructured = true },
        },
      '';
      inherit starterVersion;
      devPath = "/nix/store/fake-dev-path";
      extrasImportSpecs = [ ];
      availableDevSpecs = [ ];
    })).success
    false;
}
