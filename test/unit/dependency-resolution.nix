# Unit tests for dependency resolution logic
# Imports the real nix/lib/dependencies.nix and verifies systemPackages
# against mock dependency data and the real nixpkgs package set.
{ pkgs, testLib, ... }:

let
  inherit (pkgs) lib;

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
      "lang.missing" = [
        { name = "ghost-tool"; nixpkg = "this-package-does-not-exist-xyz"; }
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
        missing = { };
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

  # By default, an enabled extra installs both tools and runtime dependencies
  test-extra-default-installation = testLib.testEval
    "extra-default-installation"
    (namesOf (systemPackages baseCfg [ "lang.python" ]) == [ "ruff" "python3" ])
    true;

  # Nested package paths like python3Packages.ruff resolve to the real package
  test-nested-package-resolution = testLib.testEval
    "nested-package-resolution"
    (builtins.elem pkgs.python3Packages.ruff (systemPackages baseCfg [ "lang.python" ]))
    true;

  # Tools only: installRuntimeDependencies disabled
  test-extra-tools-only = testLib.testEval
    "extra-tools-only"
    (namesOf (systemPackages (lib.recursiveUpdate baseCfg {
      extras.lang.python.installRuntimeDependencies = false;
    }) [ "lang.python" ]) == [ "ruff" ])
    true;

  # Runtime dependencies only: installDependencies disabled; unmapped package managers (pip) skipped
  test-runtime-dependencies-only = testLib.testEval
    "runtime-dependencies-only"
    (namesOf (systemPackages (lib.recursiveUpdate baseCfg {
      extras.lang.python.installDependencies = false;
    }) [ "lang.python" ]) == [ "python3" ])
    true;

  # An enabled extra with both installation options set to false contributes no packages
  test-extra-with-install-disabled = testLib.testEval
    "extra-with-install-disabled"
    (systemPackages (lib.recursiveUpdate baseCfg {
      extras.lang.python.installDependencies = false;
      extras.lang.python.installRuntimeDependencies = false;
    }) [ "lang.python" ])
    [ ];

  # Tools without a nixpkgs mapping are skipped without failing the build
  test-unmapped-tool-skipped = testLib.testEval
    "unmapped-tool-skipped"
    (systemPackages baseCfg [ "lang.unmapped" ])
    [ ];

  # Mapped names that don't exist in nixpkgs resolve to null and are filtered
  test-missing-nixpkgs-package-skipped = testLib.testEval
    "missing-nixpkgs-package-skipped"
    (systemPackages baseCfg [ "lang.missing" ])
    [ ];

  # Packages appearing as both tool and runtime dependency are deduplicated
  test-packages-deduplicated = testLib.testEval
    "packages-deduplicated"
    (builtins.length (lib.filter (name: name == "go") (namesOf (systemPackages baseCfg [ "lang.go" ]))))
    1;
}
