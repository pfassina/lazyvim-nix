# Integration tests for the granular dependency control system
{ pkgs, testLib, moduleUnderTest }:

let
  moduleLib = pkgs.lib;

  # Base config for all tests
  baseConfig = {
    home.homeDirectory = "/tmp/test-deps";
    home.username = "testuser";
    home.stateVersion = "23.11";
  };

  # Helper to evaluate module with specific config
  evalModule = config:
    let
      fullConfig = {
        config = baseConfig // { programs.lazyvim = config; };
        lib = moduleLib;
        inherit pkgs;
      };
      result = moduleLib.evalModules {
        modules = [ moduleUnderTest fullConfig ];
        specialArgs = { inherit pkgs; };
      };
    in result.config;

  # Helper to check if package is in neovim.extraPackages
  hasPackage = packages: packageName:
    builtins.any (pkg:
      (pkg.pname or pkg.name or "") == packageName ||
      moduleLib.hasPrefix packageName (pkg.pname or pkg.name or "")
    ) packages;

in {
  # Test 1: installCoreDependencies = true (default) includes core dependencies
  test-core-dependencies-default = testLib.runTest "core-dependencies-default" ''
    result=$(nix-instantiate --eval --expr '
      let
        config = ${builtins.toJSON { enable = true; }};
        module = (${builtins.readFile ../../nix/module.nix}) {
          config = {
            programs.lazyvim = config;
            home.homeDirectory = "/tmp/test";
            home.username = "test";
            home.stateVersion = "23.11";
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        packages = module.config.programs.neovim.extraPackages or [];
        hasGit = builtins.any (pkg: (pkg.name or "") == "git") packages;
        hasFd = builtins.any (pkg: builtins.match "fd-.*" (pkg.name or "") != null) packages;
        hasRipgrep = builtins.any (pkg: (pkg.name or "") == "ripgrep") packages;
      in hasGit && hasFd && hasRipgrep
    ')

    if [ "$result" = "true" ]; then
      echo "✓ Core dependencies included by default"
    else
      echo "✗ Core dependencies missing with default config"
      exit 1
    fi
  '';

  # Test 2: installCoreDependencies = false excludes core dependencies
  test-core-dependencies-disabled = testLib.runTest "core-dependencies-disabled" ''
    result=$(nix-instantiate --eval --expr '
      let
        config = ${builtins.toJSON { enable = true; installCoreDependencies = false; }};
        module = (${builtins.readFile ../../nix/module.nix}) {
          config = {
            programs.lazyvim = config;
            home.homeDirectory = "/tmp/test";
            home.username = "test";
            home.stateVersion = "23.11";
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        packages = module.config.programs.neovim.extraPackages or [];
        # Should not have core deps, but may have user extraPackages
        hasGit = builtins.any (pkg: (pkg.name or "") == "git") packages;
        hasFd = builtins.any (pkg: builtins.match "fd-.*" (pkg.name or "") != null) packages;
        hasRipgrep = builtins.any (pkg: (pkg.name or "") == "ripgrep") packages;
      in !(hasGit || hasFd || hasRipgrep)
    ')

    if [ "$result" = "true" ]; then
      echo "✓ Core dependencies excluded when installCoreDependencies = false"
    else
      echo "✗ Core dependencies still present when disabled"
      exit 1
    fi
  '';

  # Test 3: Extra with installDependencies = true includes tools
  test-extra-dependencies-enabled = testLib.runTest "extra-dependencies-enabled" ''
    result=$(nix-instantiate --eval --expr '
      let
        config = ${builtins.toJSON {
          enable = true;
          installCoreDependencies = false; # Isolate test
          extras = {
            lang = {
              python = {
                enable = true;
                installDependencies = true;
                installRuntimeDependencies = false;
              };
            };
          };
        }};
        module = (${builtins.readFile ../../nix/module.nix}) {
          config = {
            programs.lazyvim = config;
            home.homeDirectory = "/tmp/test";
            home.username = "test";
            home.stateVersion = "23.11";
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        packages = module.config.programs.neovim.extraPackages or [];
        # Should have ruff (python tool) but not python3 (runtime)
        hasRuff = builtins.any (pkg: builtins.match ".*ruff.*" (pkg.name or "") != null) packages;
        hasPython = builtins.any (pkg: (pkg.name or "") == "python3") packages;
      in hasRuff && !hasPython
    ')

    if [ "$result" = "true" ]; then
      echo "✓ Extra dependencies installed when installDependencies = true"
    else
      echo "✗ Extra dependencies not working correctly"
      exit 1
    fi
  '';

  # Test 4: Extra with installRuntimeDependencies = true includes runtime deps
  test-extra-runtime-dependencies = testLib.runTest "extra-runtime-dependencies" ''
    result=$(nix-instantiate --eval --expr '
      let
        config = ${builtins.toJSON {
          enable = true;
          installCoreDependencies = false; # Isolate test
          extras = {
            lang = {
              python = {
                enable = true;
                installDependencies = false;
                installRuntimeDependencies = true;
              };
            };
          };
        }};
        module = (${builtins.readFile ../../nix/module.nix}) {
          config = {
            programs.lazyvim = config;
            home.homeDirectory = "/tmp/test";
            home.username = "test";
            home.stateVersion = "23.11";
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        packages = module.config.programs.neovim.extraPackages or [];
        # Should have python3 (runtime) but not ruff (tool)
        hasRuff = builtins.any (pkg: builtins.match ".*ruff.*" (pkg.name or "") != null) packages;
        hasPython = builtins.any (pkg: (pkg.name or "") == "python3") packages;
      in !hasRuff && hasPython
    ')

    if [ "$result" = "true" ]; then
      echo "✓ Runtime dependencies installed when installRuntimeDependencies = true"
    else
      echo "✗ Runtime dependencies not working correctly"
      exit 1
    fi
  '';

  # Test 5: Both dependency options work together
  test-both-dependency-options = testLib.runTest "both-dependency-options" ''
    result=$(nix-instantiate --eval --expr '
      let
        config = ${builtins.toJSON {
          enable = true;
          installCoreDependencies = false; # Isolate test
          extras = {
            lang = {
              python = {
                enable = true;
                installDependencies = true;
                installRuntimeDependencies = true;
              };
            };
          };
        }};
        module = (${builtins.readFile ../../nix/module.nix}) {
          config = {
            programs.lazyvim = config;
            home.homeDirectory = "/tmp/test";
            home.username = "test";
            home.stateVersion = "23.11";
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        packages = module.config.programs.neovim.extraPackages or [];
        # Should have both ruff (tool) and python3 (runtime)
        hasRuff = builtins.any (pkg: builtins.match ".*ruff.*" (pkg.name or "") != null) packages;
        hasPython = builtins.any (pkg: (pkg.name or "") == "python3") packages;
      in hasRuff && hasPython
    ')

    if [ "$result" = "true" ]; then
      echo "✓ Both tool and runtime dependencies work together"
    else
      echo "✗ Combined dependency options not working"
      exit 1
    fi
  '';

  # Test 6: Backward compatibility - existing config still works
  test-backward-compatibility = testLib.runTest "backward-compatibility" ''
    result=$(nix-instantiate --eval --expr '
      let
        # Simulate existing user config (no dependency options specified)
        config = ${builtins.toJSON {
          enable = true;
          extraPackages = []; # Empty but present
          extras = {
            lang = {
              python.enable = true;
            };
          };
        }};
        module = (${builtins.readFile ../../nix/module.nix}) {
          config = {
            programs.lazyvim = config;
            home.homeDirectory = "/tmp/test";
            home.username = "test";
            home.stateVersion = "23.11";
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        packages = module.config.programs.neovim.extraPackages or [];
        # Should have core dependencies (installCoreDependencies defaults to true)
        hasGit = builtins.any (pkg: (pkg.name or "") == "git") packages;
        hasFd = builtins.any (pkg: builtins.match "fd-.*" (pkg.name or "") != null) packages;
        # Should NOT have python tools (installDependencies defaults to false)
        hasRuff = builtins.any (pkg: builtins.match ".*ruff.*" (pkg.name or "") != null) packages;
      in hasGit && hasFd && !hasRuff
    ')

    if [ "$result" = "true" ]; then
      echo "✓ Backward compatibility maintained"
    else
      echo "✗ Backward compatibility broken"
      exit 1
    fi
  '';

  # Test 7: Multiple extras with different dependency settings
  test-multiple-extras = testLib.runTest "multiple-extras" ''
    result=$(nix-instantiate --eval --expr '
      let
        config = ${builtins.toJSON {
          enable = true;
          installCoreDependencies = false; # Isolate test
          extras = {
            lang = {
              python = {
                enable = true;
                installDependencies = true;
                installRuntimeDependencies = false;
              };
              go = {
                enable = true;
                installDependencies = false;
                installRuntimeDependencies = true;
              };
            };
          };
        }};
        module = (${builtins.readFile ../../nix/module.nix}) {
          config = {
            programs.lazyvim = config;
            home.homeDirectory = "/tmp/test";
            home.username = "test";
            home.stateVersion = "23.11";
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        packages = module.config.programs.neovim.extraPackages or [];
        # Should have ruff (python tool) and go (go runtime) but not gopls (go tool) or python3 (python runtime)
        hasRuff = builtins.any (pkg: builtins.match ".*ruff.*" (pkg.name or "") != null) packages;
        hasGo = builtins.any (pkg: (pkg.name or "") == "go") packages;
        hasGopls = builtins.any (pkg: (pkg.name or "") == "gopls") packages;
        hasPython = builtins.any (pkg: (pkg.name or "") == "python3") packages;
      in hasRuff && hasGo && !hasGopls && !hasPython
    ')

    if [ "$result" = "true" ]; then
      echo "✓ Multiple extras with different dependency settings work correctly"
    else
      echo "✗ Multiple extras dependency handling failed"
      exit 1
    fi
  '';
}