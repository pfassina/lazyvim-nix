# Regression tests for dependency system backward compatibility
{ pkgs, testLib }:

let
  lib = pkgs.lib;

  # Helper to evaluate module with a config
  evalModuleWithConfig = config:
    let
      fullConfig = {
        config = {
          home.homeDirectory = "/tmp/test";
          home.username = "testuser";
          home.stateVersion = "23.11";
          programs.lazyvim = config;
        };
        lib = lib;
        inherit pkgs;
      };
      result = lib.evalModules {
        modules = [ (import ../../nix/module.nix) fullConfig ];
        specialArgs = { inherit pkgs; };
      };
    in result.config;

in {
  # Test that existing minimal config still works
  test-minimal-config-compatibility = testLib.runTest "minimal-config-compatibility" ''
    result=$(nix-instantiate --eval --expr '
      let
        # Simulate a minimal existing user config
        config = { enable = true; };
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

        # Should work without errors and have neovim enabled
        hasNeovim = module.config.programs.neovim.enable;
        hasPackages = builtins.length (module.config.programs.neovim.extraPackages or []) > 0;

      in hasNeovim && hasPackages
    ')

    if [ "$result" = "true" ]; then
      echo "✓ Minimal config compatibility maintained"
    else
      echo "✗ Minimal config compatibility broken"
      exit 1
    fi
  '';

  # Test that existing config with extraPackages still works
  test-extrapackages-compatibility = testLib.runTest "extrapackages-compatibility" ''
    result=$(nix-instantiate --eval --expr '
      let
        # Simulate existing user config with extraPackages
        config = {
          enable = true;
          extraPackages = [ (import <nixpkgs> {}).lua-language-server ];
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
        hasLuaLS = builtins.any (pkg:
          (pkg.pname or pkg.name or "") == "lua-language-server"
        ) packages;
        hasCore = builtins.any (pkg:
          (pkg.name or "") == "git"
        ) packages;

      in hasLuaLS && hasCore  # Should have both user packages and core deps
    ')

    if [ "$result" = "true" ]; then
      echo "✓ ExtraPackages compatibility maintained"
    else
      echo "✗ ExtraPackages compatibility broken"
      exit 1
    fi
  '';

  # Test that existing extras config still works
  test-extras-compatibility = testLib.runTest "extras-compatibility" ''
    result=$(nix-instantiate --eval --expr '
      let
        # Simulate existing user config with extras
        config = {
          enable = true;
          extras = {
            lang = {
              python.enable = true;
              nix.enable = true;
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

        # Should still work and have core dependencies (since installCoreDependencies defaults to true)
        packages = module.config.programs.neovim.extraPackages or [];
        hasCore = builtins.any (pkg: (pkg.name or "") == "git") packages;

        # Check that module evaluates without errors
        hasNeovim = module.config.programs.neovim.enable;

      in hasNeovim && hasCore
    ')

    if [ "$result" = "true" ]; then
      echo "✓ Extras configuration compatibility maintained"
    else
      echo "✗ Extras configuration compatibility broken"
      exit 1
    fi
  '';

  # Test that new options have correct defaults for backward compatibility
  test-default-values-compatibility = testLib.runTest "default-values-compatibility" ''
    result=$(nix-instantiate --eval --expr '
      let
        # Test minimal config to verify defaults
        config = { enable = true; };
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

        # Check that installCoreDependencies defaults to true
        coreDepsEnabled = module.config.programs.lazyvim.installCoreDependencies;

        # Check that we get core packages by default
        packages = module.config.programs.neovim.extraPackages or [];
        hasCore = builtins.any (pkg: (pkg.name or "") == "git") packages;

      in coreDepsEnabled && hasCore
    ')

    if [ "$result" = "true" ]; then
      echo "✓ Default values maintain backward compatibility"
    else
      echo "✗ Default values break backward compatibility"
      exit 1
    fi
  '';

  # Test that existing config files approach still works
  test-configfiles-compatibility = testLib.runTest "configfiles-compatibility" ''
    # Create a temporary test config directory
    mkdir -p $TMPDIR/test-config/lua/config
    cat > $TMPDIR/test-config/lua/config/options.lua << 'EOF'
vim.opt.number = true
EOF

    result=$(nix-instantiate --eval --expr "
      let
        config = {
          enable = true;
          configFiles = $TMPDIR/test-config;
        };
        module = (${builtins.readFile ../../nix/module.nix}) {
          config = {
            programs.lazyvim = config;
            home.homeDirectory = \"/tmp/test\";
            home.username = \"test\";
            home.stateVersion = \"23.11\";
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };

        # Should work and create config files
        hasNeovim = module.config.programs.neovim.enable;
        hasConfigFile = module.config.xdg.configFile ? \"nvim/lua/config/options.lua\";

      in hasNeovim && hasConfigFile
    ")

    if [ "$result" = "true" ]; then
      echo "✓ ConfigFiles compatibility maintained"
    else
      echo "✗ ConfigFiles compatibility broken"
      exit 1
    fi
  '';

  # Test that package counts are reasonable (regression for core deps)
  test-package-count-regression = testLib.runTest "package-count-regression" ''
    result=$(nix-instantiate --eval --expr '
      let
        # Test that we get a reasonable number of core packages
        config = { enable = true; };
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

        # Should have core dependencies (git, ripgrep, fd, lazygit, fzf, curl) = 6 packages minimum
        # Note: fdfind maps to fd, so we expect 6 unique packages

      in packageCount >= 6 && packageCount <= 20  # Reasonable range
    ')

    if [ "$result" = "true" ]; then
      echo "✓ Package count is within expected range"
    else
      echo "✗ Package count regression detected"
      exit 1
    fi
  '';

  # Test that the options structure hasn't broken
  test-options-structure-compatibility = testLib.runTest "options-structure-compatibility" ''
    result=$(nix-instantiate --eval --expr '
      let
        # Test that all expected options exist and have correct types
        config = {
          enable = true;
          pluginSource = "latest";
          extraPackages = [];
          treesitterParsers = [];
          configFiles = null;
          installCoreDependencies = true;  # New option
          extras = {
            lang = {
              python = {
                enable = true;
                installDependencies = false;      # New option
                installRuntimeDependencies = false; # New option
                config = "";
              };
            };
          };
          config = {
            options = "";
            keymaps = "";
            autocmds = "";
          };
          plugins = {};
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

        # Should evaluate without errors
        hasNeovim = module.config.programs.neovim.enable;

      in hasNeovim
    ')

    if [ "$result" = "true" ]; then
      echo "✓ Options structure compatibility maintained"
    else
      echo "✗ Options structure compatibility broken"
      exit 1
    fi
  '';
}