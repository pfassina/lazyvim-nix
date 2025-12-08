# Options definition for LazyVim Nix module
{ lib }:

with lib;

{
  enable = mkEnableOption "LazyVim - A Neovim configuration framework";

  appName = mkOption {
    type = types.str;
    default = "nvim";
    example = "lazyvim";
    description = ''
      The app name for Neovim's NVIM_APPNAME environment variable.
      This determines the config directory under ~/.config/ (e.g., "lazyvim" → ~/.config/lazyvim/).
    '';
  };

  pluginSource = mkOption {
    type = types.enum [ "latest" "nixpkgs" ];
    default = "latest";
    description = ''
      Plugin source strategy:
      - "latest": Use nixpkgs if it has the required version, otherwise build from source
      - "nixpkgs": Prefer nixpkgs versions, fallback to source if unavailable
    '';
  };

  extraPackages = mkOption {
    type = types.listOf types.package;
    default = [];
    example = literalExpression ''
      with pkgs; [
        rust-analyzer
        gopls
        nodePackages.typescript-language-server
      ]
    '';
    description = ''
      Additional packages to be made available to LazyVim.
      This should include LSP servers, formatters, linters, and other tools.
    '';
  };

  treesitterParsers = mkOption {
    type = types.listOf types.package;
    default = [];
    example = literalExpression ''
      with pkgs.tree-sitter-grammars; [
        # Minimal for LazyVim itself
        tree-sitter-lua
        tree-sitter-vim
        tree-sitter-query

        # Common languages
        tree-sitter-rust
        tree-sitter-go
        tree-sitter-typescript
        tree-sitter-tsx
        tree-sitter-python
      ]
    '';
    description = ''
      List of Treesitter parser packages to install.

      Empty by default - add parsers based on languages you use.
      These should be packages from pkgs.tree-sitter-grammars.

      NOTE: Parser compatibility issues may occur if there's a version mismatch
      between nvim-treesitter and the parsers. If you see "Invalid node type"
      errors, try using a matching nixpkgs channel or pinning versions.
    '';
  };

  installCoreDependencies = mkOption {
    type = types.bool;
    default = true;
    description = ''
      Whether to automatically install core LazyVim dependencies.

      Core dependencies include: git, ripgrep, fd, lazygit, fzf, curl.

      When false, you must manually provide these tools via extraPackages
      or ensure they're available in your system PATH.
    '';
  };

  configFiles = mkOption {
    type = types.nullOr types.path;
    default = null;
    example = literalExpression ''
      ./lazyvim-config
    '';
    description = ''
      Path to a directory containing LazyVim configuration files.
      The directory structure should follow this convention:

      - config/keymaps.lua - Custom keymaps
      - config/options.lua - Vim options
      - config/autocmds.lua - Auto commands
      - plugins/*.lua - Plugin configurations

      Files from this directory will be copied to the appropriate locations
      in ~/.config/nvim/lua/. If you also specify individual config options
      (config.keymaps, config.options, etc.) or plugins, conflicts will
      cause the build to fail with a descriptive error message.
    '';
  };

  config = mkOption {
    type = types.submodule {
      options = {
        autocmds = mkOption {
          type = types.str;
          default = "";
          example = ''
            -- Auto-save on focus loss
            vim.api.nvim_create_autocmd("FocusLost", {
              command = "silent! wa",
            })
          '';
          description = ''
            Lua code for autocmds that will be written to lua/config/autocmds.lua.
            This file is loaded by LazyVim for user autocmd configurations.
          '';
        };

        keymaps = mkOption {
          type = types.str;
          default = "";
          example = ''
            -- Custom keymaps
            vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", { desc = "Save file" })
            vim.keymap.set("n", "<C-h>", "<cmd>TmuxNavigateLeft<cr>", { desc = "Go to left window" })
          '';
          description = ''
            Lua code for keymaps that will be written to lua/config/keymaps.lua.
            This file is loaded by LazyVim for user keymap configurations.
          '';
        };

        options = mkOption {
          type = types.str;
          default = "";
          example = ''
            -- Custom vim options
            vim.opt.relativenumber = false
            vim.opt.wrap = true
            vim.opt.conceallevel = 0
          '';
          description = ''
            Lua code for vim options that will be written to lua/config/options.lua.
            This file is loaded by LazyVim for user option configurations.
          '';
        };
      };
    };
    default = {};
    description = ''
      LazyVim configuration files. These map to the lua/config/ directory structure
      and are loaded by LazyVim automatically.
    '';
  };

  extras = mkOption {
    type = types.attrsOf (types.attrsOf (types.submodule {
      options = {
        enable = mkEnableOption "this LazyVim extra";

        installDependencies = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to install the main tools for this extra.

            For example, for lang.python this would install tools like 'ruff'.
            When false (default), tools must be provided via extraPackages.
          '';
        };

        installRuntimeDependencies = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to install runtime dependencies for this extra's tools.

            For example, for lang.python this would install python3 and pip.
            When false (default), runtime dependencies must be available in PATH
            or provided via extraPackages.
          '';
        };

        config = mkOption {
          type = types.str;
          default = "";
          description = ''
            Complete Lua plugin specification to override or extend this extra.
            Should contain a complete lazy.nvim plugin spec with return statement.
          '';
        };
      };
    }));
    default = {};
    example = literalExpression ''
      {
        coding.yanky = {
          enable = true;
          config = '''
            return {
              "gbprod/yanky.nvim",
              opts = {
                highlight = { timer = 300 },
              },
            }
          ''';
        };

        lang.python = {
          enable = true;
          installDependencies = true;        # Install ruff
          installRuntimeDependencies = true; # Install python3, pip
        };

        lang.go = {
          enable = true;
          installDependencies = true;        # Install gopls, gofumpt, etc.
          installRuntimeDependencies = true; # Install go compiler
        };

        lang.nix = {
          enable = true;
          config = '''
            return {
              "neovim/nvim-lspconfig",
              opts = {
                servers = {
                  nixd = {},
                },
              },
            }
          ''';
        };

        editor.dial.enable = true;
      }
    '';
    description = ''
      LazyVim extras to enable. Extras provide additional plugins and configurations
      for specific languages, features, or tools.

      Each extra can be enabled with `enable = true` and optionally configured with
      complete lazy.nvim plugin specifications in the `config` field.
    '';
  };

  ignoreBuildNotifications = mkOption {
    type = types.bool;
    default = false;
    description = ''
      Whether to suppress build notifications and trace messages.

      When enabled, this will hide:
      - Tool installation warnings (e.g., "This tool will be skipped during installation")
      - Plugin source trace messages (e.g., "LazyVim/LazyVim: Using source (v15.10.1)")
      - Package resolution warnings
      - Other build-time informational messages

      This is useful for users who want cleaner build output and are aware
      of any missing dependencies in their configuration.
    '';
  };

  plugins = mkOption {
    type = types.attrsOf types.str;
    default = {};
    example = literalExpression ''
      {
        custom-theme = '''
          return {
            "folke/tokyonight.nvim",
            opts = {
              style = "night",
              transparent = true,
            },
          }
        ''';

        lsp-config = '''
          return {
            "neovim/nvim-lspconfig",
            opts = function(_, opts)
              opts.servers.rust_analyzer = {
                settings = {
                  ["rust-analyzer"] = {
                    checkOnSave = {
                      command = "clippy",
                    },
                  },
                },
              }
            end,
          }
        ''';
      }
    '';
    description = ''
      Plugin configuration files. Each key becomes a file lua/plugins/{key}.lua
      with the corresponding Lua code. These files are automatically loaded by LazyVim.
    '';
  };
}
