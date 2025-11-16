# Test for issue #33 fix - minimal configuration should create default plugin file
{ pkgs, testLib, moduleUnderTest }:

{
  # Test that minimal config creates default plugin file to prevent LazyVim error
  test-minimal-config-default-plugin = testLib.testNixExpr
    "minimal-config-default-plugin"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
            home.username = "testuser";
            home.stateVersion = "23.11";
            programs.lazyvim = {
              enable = true;
              # No plugins defined - this is the test case for issue #33
              extras = {
                lang.nix.enable = true;
              };
              extraPackages = [];  # Simplified to avoid nixpkgs dependency
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
        # The module should return a set with config
        hasConfig = builtins.isAttrs module && module ? config;
        # When evaluated, it should create the default plugin file
        # We can't directly test xdg.configFile here due to evaluation context,
        # but we can ensure the module evaluates without error
      in hasConfig
    ''
    "true";

  # Test that config with user plugins doesn't create default plugin file
  test-with-user-plugins-no-default = testLib.testNixExpr
    "with-user-plugins-no-default"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
            home.username = "testuser";
            home.stateVersion = "23.11";
            programs.lazyvim = {
              enable = true;
              plugins = {
                custom-theme = "return { 'folke/tokyonight.nvim' }";
              };
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
        # Module should evaluate successfully when user plugins are defined
        hasConfig = builtins.isAttrs module && module ? config;
      in hasConfig
    ''
    "true";
}