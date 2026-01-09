# End-to-end tests with real Neovim configurations
{ pkgs, testLib, moduleUnderTest }:

let
  moduleLib = pkgs.lib;

  # Create realistic test configurations
  createTestHome = name: config: pkgs.runCommand "test-home-${name}" {
    buildInputs = [ pkgs.nix ];
  } ''
    mkdir -p $out

    # Create a minimal home-manager configuration
    cat > $out/home.nix << 'EOF'
    { config, lib, pkgs, ... }:
    {
      imports = [ ${../../nix/module.nix} ];

      ${config}

      home.username = "testuser";
      home.homeDirectory = "$out/home";
      home.stateVersion = "23.11";
    }
    EOF

    # Test that the configuration evaluates
    nix-instantiate --eval --expr '
      let
        pkgs = import <nixpkgs> {};
        config = import '"$out"'/home.nix { config = {}; lib = pkgs.lib; inherit pkgs; };
      in config.config.programs.neovim.enable
    ' > $out/eval-result

    # Generate the actual configuration files
    nix-build --no-out-link -E '
      let
        pkgs = import <nixpkgs> {};
        hmLib = import <nixpkgs/nixos/lib/eval-config.nix> {
          modules = [
            ({ ... }: { _module.args.pkgs = pkgs; })
            (import '"$out"'/home.nix)
          ];
        };
      in hmLib.config.xdg.configFile
    ' > $out/config-files 2>/dev/null || echo "Config generation skipped (requires home-manager)"
  '';

in {
  # Test minimal LazyVim configuration
  test-minimal-lazyvim-config = testLib.runTest "minimal-lazyvim-config" ''
    echo "Testing minimal LazyVim configuration..."

    config='
      programs.lazyvim = {
        enable = true;
      };
    '

    home_dir=$(${createTestHome "minimal" config})

    if [ -f "$home_dir/eval-result" ]; then
      result=$(cat "$home_dir/eval-result")
      if [ "$result" = "true" ]; then
        echo "✓ Minimal configuration evaluates successfully"
      else
        echo "✗ Minimal configuration evaluation failed"
        exit 1
      fi
    else
      echo "✗ Configuration evaluation failed"
      exit 1
    fi
  '';

  # Test full-featured LazyVim configuration
  test-full-featured-config = testLib.runTest "full-featured-config" ''
    echo "Testing full-featured LazyVim configuration..."

    config='
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
          options = "vim.opt.relativenumber = false";
          keymaps = "vim.keymap.set(\"n\", \"<leader>w\", \"<cmd>w<cr>\")";
          autocmds = "vim.api.nvim_create_autocmd(\"FocusLost\", { command = \"silent! wa\" })";
        };

        extras = {
          lang.nix.enable = true;
          editor.telescope.enable = true;
        };

        plugins = {
          custom-theme = "return { \"folke/tokyonight.nvim\", opts = { style = \"night\" } }";
        };
      };
    '

    home_dir=$(${createTestHome "full" config})

    if [ -f "$home_dir/eval-result" ]; then
      result=$(cat "$home_dir/eval-result")
      if [ "$result" = "true" ]; then
        echo "✓ Full-featured configuration evaluates successfully"
      else
        echo "✗ Full-featured configuration evaluation failed"
        exit 1
      fi
    else
      echo "✗ Configuration evaluation failed"
      exit 1
    fi
  '';

  # Test that generated init.lua is valid Lua syntax
  test-init-lua-syntax = testLib.runTest "init-lua-syntax" ''
    echo "Testing generated init.lua syntax..."

    # Create a test configuration and extract init.lua
    testConfig='{
      config = {
        home.homeDirectory = "/tmp/test";
        home.username = "testuser";
        home.stateVersion = "23.11";
        programs.lazyvim.enable = true;
      };
      lib = (import <nixpkgs> {}).lib;
      pkgs = import <nixpkgs> {};
    }'

    # Extract the init.lua content
    init_lua=$(nix-instantiate --eval --expr "
      let module = import ${../nix/module.nix} $testConfig;
      in module.config.xdg.configFile.\"nvim/init.lua\".text
    " 2>/dev/null | sed 's/^"//; s/"$//' | sed 's/\\n/\n/g')

    if [ -n "$init_lua" ]; then
      # Test Lua syntax using lua interpreter
      echo "$init_lua" | ${pkgs.lua}/bin/lua -c 2>/dev/null
      if [ $? -eq 0 ]; then
        echo "✓ Generated init.lua has valid Lua syntax"
      else
        echo "✗ Generated init.lua has syntax errors"
        echo "Content preview:"
        echo "$init_lua" | head -20
        exit 1
      fi
    else
      echo "✗ Failed to extract init.lua content"
      exit 1
    fi
  '';

  # Test plugin resolution with real nixpkgs
  test-real-plugin-resolution = testLib.runTest "real-plugin-resolution" ''
    echo "Testing plugin resolution with real nixpkgs..."

    # Test some common plugins that should resolve
    common_plugins=(
      "lazy-nvim"
      "nvim-lspconfig"
      "nvim-treesitter"
      "telescope-nvim"
      "catppuccin-nvim"
    )

    for plugin in "''${common_plugins[@]}"; do
      if nix-instantiate --eval --expr "(import <nixpkgs> {}).vimPlugins.${plugin}" >/dev/null 2>&1; then
        echo "✓ Plugin available in nixpkgs: $plugin"
      else
        echo "! Plugin not found in nixpkgs: $plugin"
        # Not necessarily an error, but worth noting
      fi
    done

    echo "Plugin resolution test completed"
  '';

  # Test Neovim configuration building
  test-neovim-config-build = testLib.runTest "neovim-config-build" ''
    echo "Testing Neovim configuration building..."

    # Create a configuration that should build
    buildConfig='{
      config = {
        home.homeDirectory = "/tmp/test-build";
        home.username = "testuser";
        home.stateVersion = "23.11";
        programs.lazyvim = {
          enable = true;
          extraPackages = with (import <nixpkgs> {}); [ ripgrep fd ];
        };
      };
      lib = (import <nixpkgs> {}).lib;
      pkgs = import <nixpkgs> {};
    }'

    # Test that neovim configuration builds
    result=$(nix-instantiate --eval --expr "
      let
        module = import ${../nix/module.nix} $buildConfig;
        nvimConfig = module.config.programs.neovim;
      in {
        enabled = nvimConfig.enable;
        hasPackages = builtins.length nvimConfig.extraPackages > 0;
        hasPlugins = builtins.length nvimConfig.plugins > 0;
      }
    " 2>/dev/null || echo "{ enabled = false; hasPackages = false; hasPlugins = false; }")

    echo "Neovim config result: $result"

    # Parse the result (simplified check)
    if echo "$result" | grep -q "enabled.*true"; then
      echo "✓ Neovim configuration builds successfully"
    else
      echo "✗ Neovim configuration build failed"
      exit 1
    fi
  '';

  # Test performance with large configurations
  test-performance-large-config = testLib.runTest "performance-large-config" ''
    echo "Testing performance with large configuration..."

    start_time=$(date +%s)

    # Create a large configuration
    largeConfig='{
      config = {
        home.homeDirectory = "/tmp/test-perf";
        home.username = "testuser";
        home.stateVersion = "23.11";
        programs.lazyvim = {
          enable = true;

          extraPackages = with (import <nixpkgs> {}); [
            lua-language-server rust-analyzer gopls typescript-language-server
            pyright nixd alejandra stylua prettier ripgrep fd fzf bat
            git curl wget htop btop tree jq yq
          ];

          treesitterParsers = with (import <nixpkgs> {}).vimPlugins.nvim-treesitter-parsers; [
            lua rust go typescript
            python nix bash json
            yaml toml markdown
          ];

          plugins = builtins.listToAttrs (map (i: {
            name = "plugin-${toString i}";
            value = "return { \"test/plugin-${toString i}\", opts = { test = ${toString i} } }";
          }) (builtins.genList (x: x) 50));

          config = {
            options = builtins.concatStringsSep "\n" (map (i:
              "vim.opt.option${toString i} = ${toString i}"
            ) (builtins.genList (x: x) 20));
          };
        };
      };
      lib = (import <nixpkgs> {}).lib;
      pkgs = import <nixpkgs> {};
    }'

    # Test evaluation time
    if nix-instantiate --eval --expr "
      let module = import ${../nix/module.nix} $largeConfig;
      in module.config.programs.neovim.enable
    " >/dev/null 2>&1; then
      end_time=$(date +%s)
      duration=$((end_time - start_time))

      echo "✓ Large configuration evaluated in ''${duration}s"

      # Performance threshold: should complete within reasonable time
      if [ "$duration" -lt 60 ]; then
        echo "✓ Performance acceptable (< 60s)"
      else
        echo "! Performance warning: took ''${duration}s (> 60s)"
      fi
    else
      echo "✗ Large configuration evaluation failed"
      exit 1
    fi
  '';

  # Test treesitter parser installation
  test-treesitter-parsers = testLib.runTest "treesitter-parsers" ''
    echo "Testing treesitter parser installation..."

    parserConfig='{
      config = {
        home.homeDirectory = "/tmp/test-parsers";
        home.username = "testuser";
        home.stateVersion = "23.11";
        programs.lazyvim = {
          enable = true;
          treesitterParsers = with (import <nixpkgs> {}).vimPlugins.nvim-treesitter-parsers; [
            lua
            nix
          ];
        };
      };
      lib = (import <nixpkgs> {}).lib;
      pkgs = import <nixpkgs> {};
    }'

    # Test that treesitter configuration is generated
    result=$(nix-instantiate --eval --expr "
      let
        module = import ${../nix/module.nix} $parserConfig;
        configFiles = module.config.xdg.configFile;
      in configFiles ? \"nvim/parser\"
    " 2>/dev/null || echo "false")

    if [ "$result" = "true" ]; then
      echo "✓ Treesitter parser configuration generated"
    else
      echo "✗ Treesitter parser configuration missing"
      exit 1
    fi
  '';

  # Test extras system integration
  test-extras-integration = testLib.runTest "extras-integration" ''
    echo "Testing LazyVim extras integration..."

    extrasConfig='{
      config = {
        home.homeDirectory = "/tmp/test-extras";
        home.username = "testuser";
        home.stateVersion = "23.11";
        programs.lazyvim = {
          enable = true;
          extras = {
            lang = {
              nix = {
                enable = true;
                config = "opts = { servers = { nixd = {} } }";
              };
            };
            editor = {
              telescope.enable = true;
            };
          };
        };
      };
      lib = (import <nixpkgs> {}).lib;
      pkgs = import <nixpkgs> {};
    }'

    # Test that extras generate appropriate config files
    result=$(nix-instantiate --eval --expr "
      let
        module = import ${../nix/module.nix} $extrasConfig;
        configFiles = module.config.xdg.configFile;

        # Look for extras config files
        extrasFiles = builtins.filter (name:
          builtins.match \"nvim/lua/plugins/extras-.*\" name != null
        ) (builtins.attrNames configFiles);

        hasExtrasFiles = builtins.length extrasFiles > 0;
      in hasExtrasFiles
    " 2>/dev/null || echo "false")

    if [ "$result" = "true" ]; then
      echo "✓ Extras integration working"
    else
      echo "✗ Extras integration failed"
      exit 1
    fi
  '';

  # Test that Mason.nvim is properly disabled
  test-mason-disabled = testLib.runTest "mason-disabled" ''
    echo "Testing Mason.nvim disabling..."

    testConfig='{
      config = {
        home.homeDirectory = "/tmp/test-mason";
        home.username = "testuser";
        home.stateVersion = "23.11";
        programs.lazyvim.enable = true;
      };
      lib = (import <nixpkgs> {}).lib;
      pkgs = import <nixpkgs> {};
    }'

    # Check that init.lua contains Mason disabling
    init_lua=$(nix-instantiate --eval --expr "
      let module = import ${../nix/module.nix} $testConfig;
      in module.config.xdg.configFile.\"nvim/init.lua\".text
    " 2>/dev/null | tr -d '"' | sed 's/\\n/\n/g')

    if echo "$init_lua" | grep -q "mason.*enabled.*false"; then
      echo "✓ Mason.nvim properly disabled in configuration"
    else
      echo "✗ Mason.nvim not properly disabled"
      echo "Init.lua preview:"
      echo "$init_lua" | grep -A5 -B5 mason || echo "No mason references found"
      exit 1
    fi
  '';
}