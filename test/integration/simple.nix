# Simplified integration tests
{ testLib, ... }:

{
  # Test that the module can be evaluated with minimal config
  test-module-minimal-eval = testLib.testNixExpr
    "module-minimal-eval"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
            home.username = "testuser";
            home.stateVersion = "23.11";
            programs.lazyvim.enable = true;
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        # Just test that we can import the module
        canImport = builtins.typeOf (import ${../../nix/module.nix} testConfig) == "set";
      in canImport
    ''
    "true";

  # Test that the module has expected options
  test-module-has-options = testLib.testNixExpr
    "module-has-options"
    ''
      let
        testConfig = {
          config = {};
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
        hasOptions = module ? options && module.options ? programs;
      in hasOptions
    ''
    "true";
}