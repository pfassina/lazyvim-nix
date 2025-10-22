# Unit tests for dependency resolution logic
{ pkgs, testLib }:

let
  lib = pkgs.lib;

  # Mock dependencies.json data for testing
  mockDependencies = {
    core = [
      { name = "git"; nixpkg = "git"; }
      { name = "rg"; nixpkg = "ripgrep"; }
      { name = "fd"; nixpkg = "fd"; }
    ];
    extras = {
      "lang.python" = [
        {
          name = "ruff";
          nixpkg = "python3Packages.ruff";
          runtime_dependencies = [
            { name = "python3"; nixpkg = "python3"; }
            { name = "pip"; } # No nixpkg mapping
          ];
        }
      ];
      "lang.go" = [
        {
          name = "gopls";
          nixpkg = "gopls";
          runtime_dependencies = [
            { name = "go"; nixpkg = "go"; }
          ];
        }
        {
          name = "goimports";
          nixpkg = "go"; # goimports is part of go package
          runtime_dependencies = [
            { name = "go"; nixpkg = "go"; }
          ];
        }
      ];
      "formatting.prettier" = [
        {
          name = "prettier";
          nixpkg = "nodePackages.prettier";
          runtime_dependencies = [
            { name = "nodejs"; nixpkg = "nodejs"; }
            { name = "npm"; } # No nixpkg mapping
          ];
        }
      ];
    };
  };

  # Helper to simulate resolvePackage function
  resolvePackage = pkgName:
    if pkgs ? ${pkgName} then pkgs.${pkgName}
    else null;

  # Helper to simulate core package resolution
  resolveCorePackages = installCoreDeps:
    if installCoreDeps then
      lib.filter (pkg: pkg != null) (map (tool:
        if tool ? nixpkg then resolvePackage tool.nixpkg else null
      ) mockDependencies.core)
    else [];

  # Helper to simulate extra package resolution
  resolveExtraPackages = extraName: installDeps: installRuntimeDeps:
    let
      extraTools = mockDependencies.extras.${extraName} or [];
    in
      if extraTools != [] then
        let
          # Get tool packages
          toolPackages = if installDeps then
            lib.filter (pkg: pkg != null) (map (tool:
              if tool ? nixpkg then resolvePackage tool.nixpkg else null
            ) extraTools)
          else [];

          # Get runtime dependency packages
          runtimeDependencyPackages = if installRuntimeDeps then
            lib.unique (lib.flatten (map (tool:
              if tool ? runtime_dependencies then map (dep:
                if dep ? nixpkg then resolvePackage dep.nixpkg else null
              ) tool.runtime_dependencies else []
            ) extraTools))
          else [];

          validRuntimeDeps = lib.filter (pkg: pkg != null) runtimeDependencyPackages;
        in
          toolPackages ++ validRuntimeDeps
      else [];

in {
  # Simple test for dependency resolution JSON structure
  test-expr-dependencies-json-structure = testLib.testNixExpr
    "dependencies-json-structure"
    ''
      let
        dependencies = builtins.fromJSON (builtins.readFile ../../../data/dependencies.json);
        hasCore = dependencies ? core;
        hasExtras = dependencies ? extras;
        coreIsArray = builtins.isList dependencies.core;
      in hasCore && hasExtras && coreIsArray
    ''
    true;

  # Test that dependencies.json contains expected core tools
  test-expr-core-dependencies-content = testLib.testNixExpr
    "core-dependencies-content"
    ''
      let
        dependencies = builtins.fromJSON (builtins.readFile ../../../data/dependencies.json);
        coreTools = map (tool: tool.name) dependencies.core;
        hasGit = builtins.elem "git" coreTools;
        hasRipgrep = builtins.elem "rg" coreTools;
        hasFd = builtins.elem "fd" coreTools;
      in hasGit && hasRipgrep && hasFd
    ''
    true;

  # Test that extras contain expected language configs
  test-expr-extras-structure = testLib.testNixExpr
    "extras-structure"
    ''
      let
        dependencies = builtins.fromJSON (builtins.readFile ../../../data/dependencies.json);
        extras = dependencies.extras;
        hasPython = extras ? "lang.python";
        hasGo = extras ? "lang.go";
      in hasPython && hasGo
    ''
    true;

  # Test runtime_dependencies structure in extras
  test-expr-runtime-dependencies-structure = testLib.testNixExpr
    "runtime-dependencies-structure"
    ''
      let
        dependencies = builtins.fromJSON (builtins.readFile ../../../data/dependencies.json);
        pythonTools = dependencies.extras."lang.python" or [];
        hasRuntimeDeps = builtins.any (tool: tool ? runtime_dependencies) pythonTools;
      in hasRuntimeDeps
    ''
    true;

  # Test that basic list operations work as expected
  test-expr-basic-list-operations = testLib.testNixExpr
    "basic-list-operations"
    ''
      let
        lib = (import <nixpkgs> {}).lib;
        testList = [1 2 null 3 null];
        filtered = lib.filter (x: x != null) testList;
        unique = lib.unique [1 2 2 3];
      in builtins.length filtered == 3 && builtins.length unique == 3
    ''
    true;

  # Test package availability concept
  test-expr-package-availability = testLib.testNixExpr
    "package-availability"
    ''
      let
        pkgs = import <nixpkgs> {};
        hasGit = pkgs ? git;
        hasRipgrep = pkgs ? ripgrep;
        hasFd = pkgs ? fd;
      in hasGit && hasRipgrep && hasFd
    ''
    true;
}