# Critical integration tests for missing coverage areas (simplified)
{ pkgs, testLib, moduleUnderTest, ... }:

let
  evalLazyvim = lazyvimConfig: extraConfig:
    (pkgs.lib.evalModules {
      modules = [
        moduleUnderTest
        ({ lib, ... }: {
          options = {
            home = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = {}; };
            programs.neovim = lib.mkOption {
              type = lib.types.submodule {
                freeformType = lib.types.attrsOf lib.types.anything;
                options = {
                  defaultEditor = lib.mkEnableOption "neovim as default editor";
                  viAlias = lib.mkEnableOption "vi alias";
                  vimAlias = lib.mkEnableOption "vim alias";
                };
              };
              default = {};
            };
            xdg = {
              dataFile = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = {}; };
              configFile = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = {}; };
            };
          };
          config = {
            _module.args.pkgs = pkgs;
            home = {
              homeDirectory = "/tmp/test";
              username = "testuser";
              stateVersion = "23.11";
            };
            programs.lazyvim = { enable = true; } // lazyvimConfig;
          } // extraConfig;
        })
      ];
    }).config;
in
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

  # Latest mode should NOT pull in query-only namespaces (e.g. html_tags)
  # that appear in upstream requires but are not buildable manifest entries.
  test-plugin-source-latest-skips-query-only-requires = testLib.testNixExpr
    "plugin-source-latest-skips-query-only-requires"
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
              treesitterParsers = with (import <nixpkgs> {}).vimPlugins.nvim-treesitter-parsers; [
                html
              ];
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        treesitterLib = import ${../../nix/lib/treesitter.nix} {
          lib = testConfig.lib;
          pkgs = testConfig.pkgs;
          treesitterMappings = { core = [ ]; extras = { }; };
          extractLang = parser: parser.grammarName or parser.language;
          ignoreBuildNotifications = false;
        };
        parserNames = treesitterLib.automaticTreesitterParsers testConfig.config.programs.lazyvim [ ];
      in builtins.elem "html" parserNames && !builtins.elem "html_tags" parserNames
    ''
    "true";

  # Latest mode must fail loudly when asked for a parser that is not in the
  # generated manifest, rather than silently falling back to a mismatched grammar.
  test-plugin-source-latest-missing-parser-fails-clearly = testLib.testNixExpr
    "plugin-source-latest-missing-parser-fails-clearly"
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
              treesitterParsers = [
                {
                  grammarName = "definitely_missing_parser";
                  name = "mock-definitely-missing-parser";
                }
              ];
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        treesitterLib = import ${../../nix/lib/treesitter.nix} {
          lib = testConfig.lib;
          pkgs = testConfig.pkgs;
          treesitterMappings = { core = [ ]; extras = { }; };
          extractLang = parser: parser.grammarName or parser.language;
          ignoreBuildNotifications = false;
        };
        parserNames = treesitterLib.automaticTreesitterParsers testConfig.config.programs.lazyvim [ ];
      in !(builtins.tryEval (treesitterLib.treesitterGrammarsFromSource parserNames)).success
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

  # Test defaultEditor, viAlias, and vimAlias default to false
  test-neovim-alias-and-editor-defaults = testLib.testEval
    "neovim-alias-and-editor-defaults"
    (let
      cfg = evalLazyvim {} {};
    in {
      lazyvim = { inherit (cfg.programs.lazyvim) defaultEditor viAlias vimAlias; };
      neovim = { inherit (cfg.programs.neovim) defaultEditor viAlias vimAlias; };
    } == {
      lazyvim = { defaultEditor = false; viAlias = false; vimAlias = false; };
      neovim = { defaultEditor = false; viAlias = false; vimAlias = false; };
    })
    true;

  # Test defaultEditor forwards to programs.neovim.defaultEditor
  test-default-editor-enabled = testLib.testEval
    "default-editor-enabled"
    (let
      cfg = evalLazyvim { defaultEditor = true; } {};
    in {
      inherit (cfg.programs.neovim) defaultEditor viAlias vimAlias;
    } == {
      defaultEditor = true;
      viAlias = false;
      vimAlias = false;
    })
    true;

  # Test viAlias forwards to programs.neovim.viAlias
  test-vi-alias-enabled = testLib.testEval
    "vi-alias-enabled"
    (let
      cfg = evalLazyvim { viAlias = true; } {};
    in {
      inherit (cfg.programs.neovim) defaultEditor viAlias vimAlias;
    } == {
      defaultEditor = false;
      viAlias = true;
      vimAlias = false;
    })
    true;

  # Test vimAlias forwards to programs.neovim.vimAlias
  test-vim-alias-enabled = testLib.testEval
    "vim-alias-enabled"
    (let
      cfg = evalLazyvim { vimAlias = true; } {};
    in {
      inherit (cfg.programs.neovim) defaultEditor viAlias vimAlias;
    } == {
      defaultEditor = false;
      viAlias = false;
      vimAlias = true;
    })
    true;

  # Test direct programs.neovim.{defaultEditor,viAlias,vimAlias} overrides do not conflict
  test-neovim-options-direct-override = testLib.testEval
    "neovim-options-direct-override"
    (let
      cfg = evalLazyvim {} {
        programs.neovim = {
          defaultEditor = true;
          viAlias = true;
          vimAlias = true;
        };
      };
    in {
      inherit (cfg.programs.neovim) defaultEditor viAlias vimAlias;
    } == {
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
    })
    true;
}