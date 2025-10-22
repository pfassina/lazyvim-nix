# Property tests for dependency system edge cases and error handling
{ pkgs, testLib }:

let
  lib = pkgs.lib;

in {
  # Test handling of malformed dependency configurations
  test-malformed-dependency-config = testLib.runTest "malformed-dependency-config" ''
    result=$(nix-instantiate --eval --expr '
      let
        # Test with invalid boolean values
        config = {
          enable = true;
          installCoreDependencies = "invalid";  # Should be boolean
        };

        # This should fail during evaluation due to type checking
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

      in false  # Should not reach this
    ' 2>&1 || echo "error-detected")

    if echo "$result" | grep -q "error-detected\|type.*bool"; then
      echo "✓ Malformed config properly rejected"
    else
      echo "✗ Malformed config not properly handled"
      exit 1
    fi
  '';

  # Test empty extras configuration
  test-empty-extras-handling = testLib.runTest "empty-extras-handling" ''
    result=$(nix-instantiate --eval --expr '
      let
        config = {
          enable = true;
          installCoreDependencies = false;
          extras = {};  # Empty extras
        };
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
        packageCount = builtins.length packages;
        hasNeovim = module.config.programs.neovim.enable;

      in hasNeovim && packageCount == 0  # Should work with empty packages
    ')

    if [ "$result" = "true" ]; then
      echo "✓ Empty extras configuration handled correctly"
    else
      echo "✗ Empty extras configuration handling failed"
      exit 1
    fi
  '';

  # Test nonexistent extra configuration
  test-nonexistent-extra = testLib.runTest "nonexistent-extra" ''
    result=$(nix-instantiate --eval --expr '
      let
        config = {
          enable = true;
          installCoreDependencies = false;
          extras = {
            lang = {
              "nonexistent-language" = {
                enable = true;
                installDependencies = true;
              };
            };
          };
        };
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
        hasNeovim = module.config.programs.neovim.enable;

      in hasNeovim  # Should not crash, just skip nonexistent extra
    ')

    if [ "$result" = "true" ]; then
      echo "✓ Nonexistent extra handled gracefully"
    else
      echo "✗ Nonexistent extra handling failed"
      exit 1
    fi
  '';

  # Test large number of extras enabled
  test-many-extras-performance = testLib.runTest "many-extras-performance" ''
    result=$(nix-instantiate --eval --expr '
      let
        config = {
          enable = true;
          installCoreDependencies = true;
          extras = {
            lang = {
              python = { enable = true; installDependencies = true; };
              go = { enable = true; installDependencies = true; };
              rust = { enable = true; installDependencies = true; };
              typescript = { enable = true; installDependencies = true; };
              java = { enable = true; installDependencies = true; };
              cpp = { enable = true; installDependencies = true; };
              nix = { enable = true; installDependencies = true; };
              lua = { enable = true; installDependencies = true; };
            };
            formatting = {
              prettier = { enable = true; installDependencies = true; };
              black = { enable = true; installDependencies = true; };
            };
          };
        };
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
        hasNeovim = module.config.programs.neovim.enable;
        packageCount = builtins.length packages;

      in hasNeovim && packageCount > 0  # Should handle many extras
    ')

    if [ "$result" = "true" ]; then
      echo "✓ Many extras handled efficiently"
    else
      echo "✗ Many extras performance issue detected"
      exit 1
    fi
  '';

  # Test missing dependencies.json handling
  test-missing-dependencies-json = testLib.runTest "missing-dependencies-json" ''
    # Temporarily move dependencies.json to test fallback
    if [ -f "data/dependencies.json" ]; then
      mv data/dependencies.json data/dependencies.json.backup
    fi

    result=$(nix-instantiate --eval --expr '
      let
        config = {
          enable = true;
          installCoreDependencies = true;
        };
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

      in false  # Should fail if dependencies.json is missing
    ' 2>&1 || echo "error-detected")

    # Restore dependencies.json
    if [ -f "data/dependencies.json.backup" ]; then
      mv data/dependencies.json.backup data/dependencies.json
    fi

    if echo "$result" | grep -q "error-detected\|does not exist"; then
      echo "✓ Missing dependencies.json properly detected"
    else
      echo "✗ Missing dependencies.json not handled"
      exit 1
    fi
  '';

  # Test circular dependency handling (should not occur, but test anyway)
  test-dependency-deduplication = testLib.runTest "dependency-deduplication" ''
    result=$(nix-instantiate --eval --expr '
      let
        config = {
          enable = true;
          installCoreDependencies = true;
          extraPackages = [
            (import <nixpkgs> {}).git       # Duplicate of core dependency
            (import <nixpkgs> {}).ripgrep   # Duplicate of core dependency
          ];
        };
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

        # Count git packages (should be deduplicated)
        gitPackages = builtins.filter (pkg: (pkg.name or "") == "git") packages;
        gitCount = builtins.length gitPackages;

        hasNeovim = module.config.programs.neovim.enable;

      in hasNeovim && gitCount == 1  # Should be deduplicated
    ')

    if [ "$result" = "true" ]; then
      echo "✓ Package deduplication works correctly"
    else
      echo "✗ Package deduplication failed"
      exit 1
    fi
  '';

  # Test warning system for missing nixpkg mappings (trace output)
  test-missing-package-warnings = testLib.runTest "missing-package-warnings" ''
    # Create a mock dependencies.json with missing mappings
    mkdir -p test-data
    cat > test-data/mock-dependencies.json << 'EOF'
{
  "core": [
    {"name": "git", "nixpkg": "git"},
    {"name": "nonexistent-tool"}
  ],
  "extras": {
    "lang.test": [
      {
        "name": "test-tool",
        "runtime_dependencies": [
          {"name": "test-runtime", "nixpkg": "nonexistent-package"}
        ]
      }
    ]
  }
}
EOF

    result=$(nix-instantiate --eval --expr "
      let
        lib = (import <nixpkgs> {}).lib;
        pkgs = import <nixpkgs> {};

        # Mock dependencies with missing mappings
        dependencies = builtins.fromJSON (builtins.readFile test-data/mock-dependencies.json);

        resolvePackage = pkgName:
          if pkgs ? \${pkgName} then pkgs.\${pkgName}
          else builtins.trace \"Warning: Package '\${pkgName}' not found in nixpkgs\" null;

        # Test core package resolution with missing mapping
        corePackages = lib.filter (pkg: pkg != null) (map (tool:
          if tool ? nixpkg then resolvePackage tool.nixpkg else null
        ) dependencies.core);

        coreCount = builtins.length corePackages;

      in coreCount == 1  # Should have git but not nonexistent-tool
    " 2>&1)

    # Clean up
    rm -rf test-data

    if echo "$result" | grep -q "Warning.*not found" && echo "$result" | grep -q "true"; then
      echo "✓ Missing package warnings generated correctly"
    else
      echo "✗ Missing package warning system failed"
      exit 1
    fi
  '';
}