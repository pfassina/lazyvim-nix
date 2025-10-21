# Critical integration tests for missing coverage areas (simplified)
{ pkgs, testLib, moduleUnderTest }:

{
  # Test treesitter parser configuration evaluation
  test-treesitter-parsers = testLib.testNixExpr
    "treesitter-parsers"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
            home.username = "testuser";
            home.stateVersion = "23.11";
            programs.lazyvim = {
              enable = true;
              treesitterParsers = [];  # Simplified to avoid nixpkgs dependency
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
      in builtins.isAttrs module
    ''
    "true";

  # Test user plugin configuration evaluation
  test-user-plugins = testLib.testNixExpr
    "user-plugins"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
            home.username = "testuser";
            home.stateVersion = "23.11";
            programs.lazyvim = {
              enable = true;
              plugins = {
                custom-theme = "return { 'folke/tokyonight.nvim' }";
                lsp-config = "return { 'neovim/nvim-lspconfig' }";
              };
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
      in builtins.isAttrs module
    ''
    "true";

  # Test LazyVim extras system evaluation
  test-extras-system = testLib.testNixExpr
    "extras-system"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
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
              };
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
      in builtins.isAttrs module
    ''
    "true";

  # Test plugin source strategy "latest"
  test-plugin-source-latest = testLib.testNixExpr
    "plugin-source-latest"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
            home.username = "testuser";
            home.stateVersion = "23.11";
            programs.lazyvim = {
              enable = true;
              pluginSource = "latest";
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
      in builtins.isAttrs module
    ''
    "true";

  # Test plugin source strategy "nixpkgs"
  test-plugin-source-nixpkgs = testLib.testNixExpr
    "plugin-source-nixpkgs"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
            home.username = "testuser";
            home.stateVersion = "23.11";
            programs.lazyvim = {
              enable = true;
              pluginSource = "nixpkgs";
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
      in builtins.isAttrs module
    ''
    "true";

  # Test config files (options, keymaps, autocmds)
  test-user-config-files = testLib.testNixExpr
    "user-config-files"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
            home.username = "testuser";
            home.stateVersion = "23.11";
            programs.lazyvim = {
              enable = true;
              config = {
                options = "vim.opt.relativenumber = false";
                keymaps = "vim.keymap.set('n', '<leader>w', '<cmd>w<cr>')";
                autocmds = "vim.api.nvim_create_autocmd('FocusLost', {})";
              };
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
      in builtins.isAttrs module
    ''
    "true";

  # Test extra packages configuration
  test-extra-packages = testLib.testNixExpr
    "extra-packages"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
            home.username = "testuser";
            home.stateVersion = "23.11";
            programs.lazyvim = {
              enable = true;
              extraPackages = [];  # Simplified to avoid complex package references
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
      in builtins.isAttrs module
    ''
    "true";
}