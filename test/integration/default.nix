# Integration tests for LazyVim home-manager module
{ pkgs, testLib, moduleUnderTest }:

let
  moduleLib = pkgs.lib;

  # Test configurations that represent real-world usage
  minimalConfig = {
    config = {
      home.homeDirectory = "/tmp/test-minimal";
      home.username = "testuser";
      home.stateVersion = "23.11";
      programs.lazyvim.enable = true;
    };
    lib = moduleLib;
    inherit pkgs;
  };

  fullConfig = {
    config = {
      home.homeDirectory = "/tmp/test-full";
      home.username = "testuser";
      home.stateVersion = "23.11";
      programs.lazyvim = {
        enable = true;

        pluginSource = "latest";

        extraPackages = with pkgs; [
          lua-language-server
          rust-analyzer
          ripgrep
          fd
        ];

        treesitterParsers = with pkgs.vimPlugins.nvim-treesitter-parsers; [
          lua
          rust
          nix
        ];

        config = {
          options = ''
            vim.opt.relativenumber = false
            vim.opt.wrap = true
          '';

          keymaps = ''
            vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", { desc = "Save file" })
          '';

          autocmds = ''
            vim.api.nvim_create_autocmd("FocusLost", {
              command = "silent! wa",
            })
          '';
        };

        extras = {
          lang = {
            nix = {
              enable = true;
              config = ''
                return {
                  "neovim/nvim-lspconfig",
                  opts = {
                    servers = {
                      nixd = {},
                    },
                  },
                }
              '';
            };
          };

          editor = {
            telescope.enable = true;
          };
        };

        plugins = {
          custom-theme = ''
            return {
              "folke/tokyonight.nvim",
              opts = {
                style = "night",
                transparent = true,
              },
            }
          '';
        };
      };
    };
    lib = moduleLib;
    inherit pkgs;
  };

  # Config with only extras enabled
  extrasOnlyConfig = {
    config = {
      home.homeDirectory = "/tmp/test-extras";
      home.username = "testuser";
      home.stateVersion = "23.11";
      programs.lazyvim = {
        enable = true;

        extras = {
          coding = {
            yanky.enable = true;
          };
          lang = {
            python.enable = true;
            typescript.enable = true;
          };
          editor = {
            "neo-tree".enable = true;
          };
        };
      };
    };
    lib = moduleLib;
    inherit pkgs;
  };

in {
  # Test minimal configuration evaluation
  test-minimal-config-eval = testLib.runTest "minimal-config-eval" ''
    # Test that minimal config evaluates without errors
    nix-instantiate --eval --expr 'let module = import ${../nix/module.nix} ${builtins.toJSON minimalConfig}; in module.config.programs.neovim.enable' > /dev/null
    echo "Minimal config evaluation successful"
  '';

  # Test full configuration evaluation
  test-full-config-eval = testLib.runTest "full-config-eval" ''
    # Test that full config with all options evaluates
    nix-instantiate --eval --expr 'let module = import ${../nix/module.nix} ${builtins.toJSON fullConfig}; in module.config.programs.neovim.enable' > /dev/null
    echo "Full config evaluation successful"
  '';

  # Test that required packages are included
  test-extra-packages-inclusion = testLib.runTest "extra-packages-inclusion" ''
    # Test that extraPackages are properly included in neovim.extraPackages
    result=$(nix-instantiate --eval --expr '
      let
        module = import ${../nix/module.nix} ${builtins.toJSON fullConfig};
        packages = module.config.programs.neovim.extraPackages;
        hasLuaLS = builtins.any (pkg: pkg.pname or "" == "lua-language-server") packages;
        hasRipgrep = builtins.any (pkg: pkg.pname or "" == "ripgrep") packages;
      in hasLuaLS && hasRipgrep
    ')
    [ "$result" = "true" ]
  '';

  # Test XDG config file generation
  test-xdg-config-file-generation = testLib.runTest "xdg-config-file-generation" ''
    # Test that XDG config files are properly generated
    result=$(nix-instantiate --eval --expr '
      let
        module = import ${../nix/module.nix} ${builtins.toJSON fullConfig};
        configFiles = module.config.xdg.configFile;
        hasInitLua = configFiles ? "nvim/init.lua";
        hasOptionsLua = configFiles ? "nvim/lua/config/options.lua";
        hasKeymapsLua = configFiles ? "nvim/lua/config/keymaps.lua";
        hasCustomPlugin = configFiles ? "nvim/lua/plugins/custom-theme.lua";
      in hasInitLua && hasOptionsLua && hasKeymapsLua && hasCustomPlugin
    ')
    [ "$result" = "true" ]
  '';

  # Test treesitter parser linking
  test-treesitter-parser-linking = testLib.runTest "treesitter-parser-linking" ''
    # Test that treesitter parsers are properly linked
    result=$(nix-instantiate --eval --expr '
      let
        module = import ${../nix/module.nix} ${builtins.toJSON fullConfig};
        configFiles = module.config.xdg.configFile;
        hasParserDir = configFiles ? "nvim/parser";
      in hasParserDir
    ')
    [ "$result" = "true" ]
  '';

  # Test extras configuration processing
  test-extras-processing = testLib.runTest "extras-processing" ''
    # Test that extras are properly processed and config files generated
    result=$(nix-instantiate --eval --expr '
      let
        module = import ${../nix/module.nix} ${builtins.toJSON extrasOnlyConfig};
        configFiles = module.config.xdg.configFile;

        # Look for extras config files (pattern: nvim/lua/plugins/extras-*)
        extrasFiles = builtins.filter (name:
          builtins.match "nvim/lua/plugins/extras-.*" name != null
        ) (builtins.attrNames configFiles);

        hasExtrasFiles = builtins.length extrasFiles > 0;
      in hasExtrasFiles
    ')
    [ "$result" = "true" ]
  '';

  # Test init.lua generation with correct structure
  test-init-lua-structure = testLib.runTest "init-lua-structure" ''
    # Test that init.lua has the expected LazyVim structure
    result=$(nix-instantiate --eval --expr '
      let
        module = import ${../nix/module.nix} ${builtins.toJSON fullConfig};
        initLua = module.config.xdg.configFile."nvim/init.lua".text;

        # Check for key components
        hasLazySetup = builtins.match ".*require.*lazy.*setup.*" initLua != null;
        hasMasonDisabled = builtins.match ".*mason.*enabled.*false.*" initLua != null;
        hasDevPath = builtins.match ".*dev.*path.*" initLua != null;
        hasLazyVimImport = builtins.match ".*LazyVim/LazyVim.*" initLua != null;
      in hasLazySetup && hasMasonDisabled && hasDevPath && hasLazyVimImport
    ')
    [ "$result" = "true" ]
  '';

  # Test plugin source strategy handling
  test-plugin-source-strategy = testLib.runTest "plugin-source-strategy" ''
    # Test both "latest" and "nixpkgs" strategies work
    for strategy in "latest" "nixpkgs"; do
      echo "Testing strategy: $strategy"

      testConfig='{
        config = {
          home.homeDirectory = "/tmp/test";
          home.username = "testuser";
          home.stateVersion = "23.11";
          programs.lazyvim = {
            enable = true;
            pluginSource = "'$strategy'";
          };
        };
        lib = (import <nixpkgs> {}).lib;
        pkgs = import <nixpkgs> {};
      }'

      result=$(nix-instantiate --eval --expr "
        let module = import ${../nix/module.nix} $testConfig;
        in module.config.programs.neovim.enable
      ")

      [ "$result" = "true" ] || exit 1
    done

    echo "Plugin source strategy test passed"
  '';

  # Test that lazy.nvim is included as a plugin
  test-lazy-nvim-plugin-inclusion = testLib.runTest "lazy-nvim-plugin-inclusion" ''
    # Test that lazy.nvim is properly included in neovim plugins
    result=$(nix-instantiate --eval --expr '
      let
        module = import ${../nix/module.nix} ${builtins.toJSON minimalConfig};
        plugins = module.config.programs.neovim.plugins;
        hasLazyNvim = builtins.any (plugin:
          (plugin.pname or "") == "lazy-nvim" ||
          (plugin.name or "") == "lazy.nvim"
        ) plugins;
      in hasLazyNvim
    ')
    [ "$result" = "true" ]
  '';

  # Test that neovim is enabled and configured properly
  test-neovim-program-config = testLib.runTest "neovim-program-config" ''
    # Test neovim program configuration
    result=$(nix-instantiate --eval --expr '
      let
        module = import ${../nix/module.nix} ${builtins.toJSON fullConfig};
        nvimConfig = module.config.programs.neovim;

        isEnabled = nvimConfig.enable;
        hasNodeJs = nvimConfig.withNodeJs;
        hasPython3 = nvimConfig.withPython3;
        hasRuby = !nvimConfig.withRuby;  # Should be false (disabled)
      in isEnabled && hasNodeJs && hasPython3 && hasRuby
    ')
    [ "$result" = "true" ]
  '';

  # Test configuration file content validation
  test-config-file-content = testLib.runTest "config-file-content" ''
    # Test that generated config files have expected content
    module_result=$(nix-instantiate --eval --expr '
      let
        module = import ${../nix/module.nix} ${builtins.toJSON fullConfig};
        optionsContent = module.config.xdg.configFile."nvim/lua/config/options.lua".text;
        keymapsContent = module.config.xdg.configFile."nvim/lua/config/keymaps.lua".text;

        hasRelativeNumber = builtins.match ".*relativenumber.*false.*" optionsContent != null;
        hasSaveKeymap = builtins.match ".*leader.*w.*" keymapsContent != null;
      in hasRelativeNumber && hasSaveKeymap
    ')
    [ "$module_result" = "true" ]
  '';

  # Test module with no optional configurations
  test-minimal-module-options = testLib.runTest "minimal-module-options" ''
    # Test that module works with minimal options (only enable = true)
    minimalTestConfig='{
      config = {
        home.homeDirectory = "/tmp/test-min";
        home.username = "testuser";
        home.stateVersion = "23.11";
        programs.lazyvim.enable = true;
      };
      lib = (import <nixpkgs> {}).lib;
      pkgs = import <nixpkgs> {};
    }'

    result=$(nix-instantiate --eval --expr "
      let module = import ${../nix/module.nix} $minimalTestConfig;
      in module.config.programs.neovim.enable &&
         module.config.xdg.configFile ? \"nvim/init.lua\"
    ")
    [ "$result" = "true" ]
  '';

  # Test configFiles option functionality
  test-config-files-basic = testLib.testShell
    "config-files-basic"
    ''
    # Create a test config directory
    mkdir -p $TMPDIR/test-config/lua/config
    mkdir -p $TMPDIR/test-config/lua/plugins

    # Create test config files
    cat > $TMPDIR/test-config/lua/config/keymaps.lua << 'EOF'
    -- Test keymaps from configFiles
    vim.keymap.set("n", "<leader>t", "<cmd>echo 'test'<cr>", { desc = "Test" })
    EOF

    cat > $TMPDIR/test-config/lua/config/options.lua << 'EOF'
    -- Test options from configFiles
    vim.opt.number = true
    vim.opt.relativenumber = true
    EOF

    cat > $TMPDIR/test-config/lua/plugins/test-plugin.lua << 'EOF'
    return {
      "test/plugin",
      opts = { test = true },
    }
    EOF

    # Test module evaluation with configFiles
    testConfig='{
      config = {
        home.homeDirectory = "/tmp/test-configfiles";
        home.username = "testuser";
        home.stateVersion = "23.11";
        programs.lazyvim = {
          enable = true;
          configFiles = '$TMPDIR'/test-config;
        };
      };
      lib = (import <nixpkgs> {}).lib;
      pkgs = import <nixpkgs> {};
    }'

    result=$(nix-instantiate --eval --expr "
      let
        module = import ${../nix/module.nix} $testConfig;
        configFiles = module.config.xdg.configFile;
        hasKeymaps = configFiles ? \"nvim/lua/config/keymaps.lua\";
        hasOptions = configFiles ? \"nvim/lua/config/options.lua\";
        hasPlugin = configFiles ? \"nvim/lua/plugins/test-plugin.lua\";
      in hasKeymaps && hasOptions && hasPlugin
    " 2>/dev/null || echo "false")

    [ "$result" = "true" ]
  '';

  # Test configFiles conflict detection for config files
  test-config-files-conflict-config = testLib.testShell
    "config-files-conflict-config"
    ''
    # Create a test config directory with keymaps
    mkdir -p $TMPDIR/test-conflict/lua/config
    cat > $TMPDIR/test-conflict/lua/config/keymaps.lua << 'EOF'
    vim.keymap.set("n", "<leader>t", "<cmd>echo 'test'<cr>", { desc = "Test" })
    EOF

    # Test that conflict is detected
    testConfig='{
      config = {
        home.homeDirectory = "/tmp/test-conflict";
        home.username = "testuser";
        home.stateVersion = "23.11";
        programs.lazyvim = {
          enable = true;
          configFiles = '$TMPDIR'/test-conflict;
          config.keymaps = "vim.keymap.set(\"n\", \"<leader>x\", \"<cmd>quit<cr>\")";
        };
      };
      lib = (import <nixpkgs> {}).lib;
      pkgs = import <nixpkgs> {};
    }'

    # This should fail with a conflict error
    result=$(nix-instantiate --eval --expr "
      let module = import ${../nix/module.nix} $testConfig;
      in module.config.programs.neovim.enable
    " 2>&1 || echo "conflict-detected")

    echo "$result" | grep -q "Conflict.*keymaps"
  '';

  # Test configFiles conflict detection for plugins
  test-config-files-conflict-plugins = testLib.testShell
    "config-files-conflict-plugins"
    ''
    # Create a test config directory with a plugin file
    mkdir -p $TMPDIR/test-plugin-conflict/lua/plugins
    cat > $TMPDIR/test-plugin-conflict/lua/plugins/colorscheme.lua << 'EOF'
    return { "folke/tokyonight.nvim" }
    EOF

    # Test that conflict is detected
    testConfig='{
      config = {
        home.homeDirectory = "/tmp/test-plugin-conflict";
        home.username = "testuser";
        home.stateVersion = "23.11";
        programs.lazyvim = {
          enable = true;
          configFiles = '$TMPDIR'/test-plugin-conflict;
          plugins.colorscheme = "return { \"catppuccin/nvim\" }";
        };
      };
      lib = (import <nixpkgs> {}).lib;
      pkgs = import <nixpkgs> {};
    }'

    # This should fail with a conflict error
    result=$(nix-instantiate --eval --expr "
      let module = import ${../nix/module.nix} $testConfig;
      in module.config.programs.neovim.enable
    " 2>&1 || echo "conflict-detected")

    echo "$result" | grep -q "Conflict.*colorscheme"
  '';

  # Test configFiles with flat directory structure
  test-config-files-flat-structure = testLib.testShell
    "config-files-flat-structure"
    ''
    # Create a test config directory with flat structure
    mkdir -p $TMPDIR/test-flat/config
    mkdir -p $TMPDIR/test-flat/plugins

    cat > $TMPDIR/test-flat/config/keymaps.lua << 'EOF'
    vim.keymap.set("n", "<leader>f", "<cmd>echo 'flat'<cr>", { desc = "Flat" })
    EOF

    cat > $TMPDIR/test-flat/plugins/flat-plugin.lua << 'EOF'
    return { "test/flat-plugin" }
    EOF

    # Test module evaluation with flat structure
    testConfig='{
      config = {
        home.homeDirectory = "/tmp/test-flat";
        home.username = "testuser";
        home.stateVersion = "23.11";
        programs.lazyvim = {
          enable = true;
          configFiles = '$TMPDIR'/test-flat;
        };
      };
      lib = (import <nixpkgs> {}).lib;
      pkgs = import <nixpkgs> {};
    }'

    result=$(nix-instantiate --eval --expr "
      let
        module = import ${../nix/module.nix} $testConfig;
        configFiles = module.config.xdg.configFile;
        hasKeymaps = configFiles ? \"nvim/lua/config/keymaps.lua\";
        hasPlugin = configFiles ? \"nvim/lua/plugins/flat-plugin.lua\";
      in hasKeymaps && hasPlugin
    " 2>/dev/null || echo "false")

    [ "$result" = "true" ]
  '';

  # Test configFiles with missing directory
  test-config-files-missing-dir = testLib.testShell
    "config-files-missing-dir"
    ''
    # Test that missing directory throws appropriate error
    testConfig='{
      config = {
        home.homeDirectory = "/tmp/test-missing";
        home.username = "testuser";
        home.stateVersion = "23.11";
        programs.lazyvim = {
          enable = true;
          configFiles = /nonexistent/path;
        };
      };
      lib = (import <nixpkgs> {}).lib;
      pkgs = import <nixpkgs> {};
    }'

    result=$(nix-instantiate --eval --expr "
      let module = import ${../nix/module.nix} $testConfig;
      in module.config.programs.neovim.enable
    " 2>&1 || echo "error-detected")

    echo "$result" | grep -q "does not exist"
  '';
} // (import ./dependency-system.nix { inherit pkgs testLib; moduleUnderTest = ../nix/module.nix; })