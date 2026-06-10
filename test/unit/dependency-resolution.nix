# Unit tests for dependency resolution logic
# Imports the real nix/lib/dependencies.nix and verifies systemPackages
# against mock dependency data and the real nixpkgs package set.
{ pkgs, testLib, moduleUnderTest }:

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
            { name = "pip"; } # Package manager, intentionally unmapped
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
      "lang.unmapped" = [
        { name = "exotic-tool"; } # No nixpkg mapping at all
      ];
    };
  };

  # The real dependencies library under test
  depsLib = import ../../nix/lib/dependencies.nix {
    inherit lib pkgs;
    dependencies = mockDependencies;
    ignoreBuildNotifications = true;
  };

  inherit (depsLib) systemPackages;

  baseCfg = {
    enable = true;
    installCoreDependencies = false;
    extras = {
      lang = {
        python = { };
        go = { };
        unmapped = { };
      };
    };
  };

  namesOf = packages: map lib.getName packages;

in {
  # Disabled module yields no packages
  test-system-packages-disabled = testLib.testEval
    "system-packages-disabled"
    (systemPackages (baseCfg // { enable = false; }) [ "lang.python" ])
    [ ];

  # Core dependencies are resolved when installCoreDependencies is enabled
  test-core-packages-installed = testLib.testEval
    "core-packages-installed"
    (namesOf (systemPackages (baseCfg // { installCoreDependencies = true; }) [ ]) ==
      [ "git" "ripgrep" "fd" ])
    true;

  # Core dependencies are skipped when installCoreDependencies is disabled
  test-core-packages-skipped = testLib.testEval
    "core-packages-skipped"
    (systemPackages baseCfg [ ])
    [ ];

  # Extra tools are installed only when installDependencies is set
  test-extra-tools-installed = testLib.testEval
    "extra-tools-installed"
    (namesOf (systemPackages (lib.recursiveUpdate baseCfg {
      extras.lang.python.installDependencies = true;
    }) [ "lang.python" ]) == [ "ruff" ])
    true;

  # Nested package paths like python3Packages.ruff resolve to the real package
  test-nested-package-resolution = testLib.testEval
    "nested-package-resolution"
    (builtins.elem pkgs.python3Packages.ruff (systemPackages (lib.recursiveUpdate baseCfg {
      extras.lang.python.installDependencies = true;
    }) [ "lang.python" ]))
    true;

  # Runtime dependencies are installed only when installRuntimeDependencies is
  # set; unmapped package managers (pip) are skipped silently
  test-runtime-dependencies-installed = testLib.testEval
    "runtime-dependencies-installed"
    (namesOf (systemPackages (lib.recursiveUpdate baseCfg {
      extras.lang.python.installRuntimeDependencies = true;
    }) [ "lang.python" ]) == [ "python3" ])
    true;

  # An enabled extra with no installation options contributes no packages
  test-extra-without-install-options = testLib.testEval
    "extra-without-install-options"
    (systemPackages baseCfg [ "lang.python" ])
    [ ];

  # Tools without a nixpkgs mapping are skipped without failing the build
  test-unmapped-tool-skipped = testLib.testEval
    "unmapped-tool-skipped"
    (systemPackages (lib.recursiveUpdate baseCfg {
      extras.lang.unmapped.installDependencies = true;
    }) [ "lang.unmapped" ])
    [ ];

  # Packages appearing as both tool and runtime dependency are deduplicated
  test-packages-deduplicated = testLib.testEval
    "packages-deduplicated"
    (builtins.length (lib.filter (name: name == "go") (namesOf (systemPackages (lib.recursiveUpdate baseCfg {
      extras.lang.go.installDependencies = true;
      extras.lang.go.installRuntimeDependencies = true;
    }) [ "lang.go" ]))))
    1;
}
