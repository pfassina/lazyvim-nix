# Mappings from LazyVim plugin names to nixpkgs vimPlugins names
# This file handles the cases where automatic name resolution fails
#
# Automatic resolution converts plugin names as follows:
#   1. Takes the repository name (after the /)
#   2. Replaces hyphens (-) with underscores (_)
#   3. Replaces dots (.) with hyphens (-)
#
# Examples of automatic resolution:
#   "owner/plugin.nvim" -> "plugin-nvim"
#   "owner/plugin-name" -> "plugin_name"
#   "owner/plugin-name.nvim" -> "plugin_name-nvim"
#
# Multi-module plugin support:
# Some plugins (like mini.nvim) provide multiple modules from a single package.
# LazyVim treats each module as a separate plugin, but they all come from the same
# nixpkgs package. Use this format for multi-module plugins:
#
#   "owner/plugin.module" = { package = "nixpkgs-name"; module = "module-name"; };
#
# This creates a symlink from "module-name" to "nixpkgs-name" in the dev path,
# allowing LazyVim to find each module individually while using the same Nix package.

{
  # Mini.nvim modules (multi-module plugin: single package with multiple modules)
  # LazyVim 15.x uses nvim-mini organization (renamed from echasnovski)
  "nvim-mini/mini.ai" = { package = "mini-nvim"; module = "mini.ai"; };
  "nvim-mini/mini.bufremove" = { package = "mini-nvim"; module = "mini.bufremove"; };
  "nvim-mini/mini.comment" = { package = "mini-nvim"; module = "mini.comment"; };
  "nvim-mini/mini.diff" = { package = "mini-nvim"; module = "mini.diff"; };
  "nvim-mini/mini.icons" = { package = "mini-nvim"; module = "mini.icons"; };
  "nvim-mini/mini.indentscope" = { package = "mini-nvim"; module = "mini.indentscope"; };
  "nvim-mini/mini.move" = { package = "mini-nvim"; module = "mini.move"; };
  "nvim-mini/mini.pairs" = { package = "mini-nvim"; module = "mini.pairs"; };
  "nvim-mini/mini.starter" = { package = "mini-nvim"; module = "mini.starter"; };
  "nvim-mini/mini.surround" = { package = "mini-nvim"; module = "mini.surround"; };

  # Legacy mini.nvim references (LazyVim extras still use these)
  "echasnovski/mini.icons" = { package = "mini-nvim"; module = "mini.icons"; };

  # TESTING: Commented out to test automatic resolution
  # "L3MON4D3/LuaSnip" = "luasnip";
  # "catppuccin/nvim" = "catppuccin-nvim";
  # "folke/ts-comments.nvim" = "ts-comments-nvim";
  # "MagicDuck/grug-far.nvim" = "grug-far-nvim";
  # "nvim-neo-tree/neo-tree.nvim" = "neo-tree-nvim";
  # "nvim-lualine/lualine.nvim" = "lualine-nvim";
  # "akinsho/bufferline.nvim" = "bufferline-nvim";
  # "folke/noice.nvim" = "noice-nvim";
  # "MunifTanjim/nui.nvim" = "nui-nvim";
  # "rcarriga/nvim-notify" = "nvim-notify";
  
  # TESTING: Commented out to test automatic resolution
  # "RRethy/vim-illuminate" = "vim-illuminate";
  # "JoosepAlviste/nvim-ts-context-commentstring" = "nvim-ts-context-commentstring";
  
  # TESTING: Commented out to test automatic resolution
  # "LazyVim/LazyVim" = "LazyVim";
  
  # TESTING: Commented out to test automatic resolution
  # "folke/todo-comments.nvim" = "todo-comments-nvim";
  # "folke/which-key.nvim" = "which-key-nvim";
  # "lukas-reineke/indent-blankline.nvim" = "indent-blankline-nvim";
  # "nvim-telescope/telescope-fzf-native.nvim" = "telescope-fzf-native-nvim";
  # "nvim-tree/nvim-web-devicons" = "nvim-web-devicons";
  # "simrat39/rust-tools.nvim" = "rust-tools-nvim";
  # "akinsho/flutter-tools.nvim" = "flutter-tools-nvim";
  # "jose-elias-alvarez/typescript.nvim" = "typescript-nvim";
  # "smjonas/inc-rename.nvim" = "inc-rename-nvim";
  # "jay-babu/mason-nvim-dap.nvim" = "mason-nvim-dap";
  # "stevearc/conform.nvim" = "conform-nvim";
  # "mason-org/mason.nvim" = "mason-nvim";
  # "mason-org/mason-lspconfig.nvim" = "mason-lspconfig-nvim";
  
  # TESTING: Commented out to test automatic resolution
  # "folke/lazy.nvim" = "lazy-nvim";
  # "folke/lazydev.nvim" = "lazydev-nvim";
  # "folke/tokyonight.nvim" = "tokyonight-nvim";
  # "folke/flash.nvim" = "flash-nvim";
  # "folke/trouble.nvim" = "trouble-nvim";
  # "folke/persistence.nvim" = "persistence-nvim";
  
  # TESTING: Commented out to test automatic resolution
  # "folke/snacks.nvim" = "snacks-nvim";
  
  # TESTING: Commented out to test automatic resolution
  # "lewis6991/gitsigns.nvim" = "gitsigns-nvim";
  
  # TESTING: Commented out to test automatic resolution
  # "dstein64/vim-startuptime" = "vim-startuptime";
  # "nvim-treesitter/nvim-treesitter" = "nvim-treesitter";
  # "nvim-treesitter/nvim-treesitter-textobjects" = "nvim-treesitter-textobjects";
  # "nvim-treesitter/nvim-treesitter-context" = "nvim-treesitter-context";
  # "windwp/nvim-ts-autotag" = "nvim-ts-autotag";
  # "neovim/nvim-lspconfig" = "nvim-lspconfig";
  # "hrsh7th/nvim-cmp" = "nvim-cmp";
  # "hrsh7th/cmp-nvim-lsp" = "cmp-nvim-lsp";
  # "hrsh7th/cmp-buffer" = "cmp-buffer";
  # "hrsh7th/cmp-path" = "cmp-path";
  # "rafamadriz/friendly-snippets" = "friendly-snippets";
  # "mfussenegger/nvim-dap" = "nvim-dap";
  # "rcarriga/nvim-dap-ui" = "nvim-dap-ui";
  # "theHamsta/nvim-dap-virtual-text" = "nvim-dap-virtual-text";
  # "nvimdev/dashboard-nvim" = "dashboard-nvim";
  # "goolord/alpha-nvim" = "alpha-nvim";
  # "nvim-neotest/neotest-go" = "neotest-go";
  # "nvim-neotest/neotest-python" = "neotest-python";
  # "nvim-neotest/neotest-plenary" = "neotest-plenary";
  # "nvim-neotest/neotest-vim-test" = "neotest-vim-test";
  # "saghen/blink.cmp" = "blink-cmp";
  # "ibhagwan/fzf-lua" = "fzf-lua";
  # "kdheepak/lazygit.nvim" = "lazygit-nvim";
  # "folke/neoconf.nvim" = "neoconf-nvim";
  # "folke/neodev.nvim" = "neodev-nvim";
  # "nvim-lua/plenary.nvim" = "plenary-nvim";
  # "kevinhwang91/nvim-ufo" = "nvim-ufo";
  # "kevinhwang91/promise-async" = "promise-async";
  # "windwp/nvim-autopairs" = "nvim-autopairs";
  # "mfussenegger/nvim-lint" = "nvim-lint";

  # TESTING: Commented out to test automatic resolution
  # "p00f/clangd_extensions.nvim" = "clangd_extensions-nvim";
  # "mfussenegger/nvim-jdtls" = "nvim-jdtls";
  # "b0o/SchemaStore.nvim" = "SchemaStore-nvim";
  # "nvim-neotest/neotest" = "neotest";
  # "julienvincent/nvim-paredit" = "nvim-paredit";
  # "m00qek/baleia.nvim" = "baleia-nvim";
  # "Olical/conjure" = "conjure";
  # "mrcjkb/haskell-tools.nvim" = "haskell-tools-nvim";
  # "mrcjkb/haskell-snippets.nvim" = "haskell-snippets-nvim";
  # "luc-tielen/telescope_hoogle" = "telescope_hoogle";
  # "Hoffs/omnisharp-extended-lsp.nvim" = "omnisharp-extended-lsp-nvim";
  # "nvimtools/none-ls.nvim" = "none-ls-nvim";
  # "iamcco/markdown-preview.nvim" = "markdown-preview-nvim";
  # "MeanderingProgrammer/render-markdown.nvim" = "render-markdown-nvim";
  # "lervag/vimtex" = "vimtex";
  # "tpope/vim-dadbod" = "vim-dadbod";
  # "kristijanhusak/vim-dadbod-completion" = "vim-dadbod-completion";
  # "kristijanhusak/vim-dadbod-ui" = "vim-dadbod-ui";
  # "folke/edgy.nvim" = "edgy-nvim";
  # "towolf/vim-helm" = "vim-helm";
  # "nvim-telescope/telescope.nvim" = "telescope-nvim";
  # "Civitasv/cmake-tools.nvim" = "cmake-tools-nvim";
  # "scalameta/nvim-metals" = "nvim-metals";
  # "CopilotC-Nvim/CopilotChat.nvim" = "CopilotChat-nvim";
  # "pwntester/octo.nvim" = "octo-nvim";
  # "ahmedkhalf/project.nvim" = "project-nvim";
  # "ggandor/flit.nvim" = "flit-nvim";
  # "ggandor/leap.nvim" = "leap-nvim";
  # "tpope/vim-repeat" = "vim-repeat";
  # "stevearc/overseer.nvim" = "overseer-nvim";
  # "hedyhli/outline.nvim" = "outline-nvim";
  # "stevearc/aerial.nvim" = "aerial-nvim";
  # "ThePrimeagen/refactoring.nvim" = "refactoring-nvim";
  # "SmiteshP/nvim-navic" = "nvim-navic";
  # "R-nvim/R.nvim" = "R-nvim";
  # "mfussenegger/nvim-ansible" = "nvim-ansible";
  # "alker0/chezmoi.vim" = "chezmoi-vim";
  # "xvzc/chezmoi.nvim" = "chezmoi-nvim";

  # Note: New plugins from LazyVim v15.10.1 (2025-10-20) should all work automatically:
  # - "qvalentin/helm-ls.nvim" -> "helm-ls-nvim" (pattern 1)
  # - "chomosuke/typst-preview.nvim" -> "typst-preview-nvim" (pattern 1)
  # - "ldelossa/gh.nvim" -> "gh-nvim" (pattern 1)
  # - "ldelossa/litee.nvim" -> "litee-nvim" (pattern 1)
}