# lazyvim-nix

A bleeding edge Nix flake for [LazyVim](https://www.lazyvim.org/) that automatically tracks LazyVim releases and provides zero-configuration setup for NixOS and home-manager users.

**🚀 Always up-to-date**: Automatically tracks LazyVim releases and uses the latest plugin versions at the time of each LazyVim release.

[![Documentation](https://img.shields.io/badge/docs-wiki-blue)](https://github.com/pfassina/lazyvim-nix/wiki)

## Quick Start

Add to your flake inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    lazyvim.url = "github:pfassina/lazyvim-nix";
  };

  outputs = { nixpkgs, home-manager, lazyvim, ... }: {
    # Your system configuration
  };
}
```

Enable in your home-manager configuration:

```nix
{
  imports = [ lazyvim.homeManagerModules.default ];
  programs.lazyvim.enable = true;
}
```

That's it! Open `nvim` and enjoy LazyVim.

### Version Pinning

Pin to a specific LazyVim release:
```nix
lazyvim.url = "github:pfassina/lazyvim-nix/v15.13.0";  # Pin to v15.13.0
```

## Basic Configuration

### Language Support

```nix
programs.lazyvim = {
  enable = true;

  extras = {
    lang.nix.enable = true;
    lang.python = {
      enable = true;
      installDependencies = true;        # Install ruff
      installRuntimeDependencies = true; # Install python3
    };
    lang.go = {
      enable = true;
      installDependencies = true;        # Install gopls, gofumpt, etc.
      installRuntimeDependencies = true; # Install go compiler
    };
  };

  # Additional packages (optional)
  extraPackages = with pkgs; [
    nixd       # Nix LSP
    alejandra  # Nix formatter
  ];

  # Only needed for languages not covered by LazyVim extras
  treesitterParsers = with pkgs.vimPlugins.nvim-treesitter-parsers; [
    wgsl      # WebGPU Shading Language
    templ     # Go templ files
  ];
};
```

**Note:** Treesitter grammars are [installed automatically](https://github.com/pfassina/lazyvim-nix/wiki/Configuration-Reference#treesitterparsers) based on enabled language extras.

### Dependency Control

Control which packages get installed automatically:

```nix
programs.lazyvim = {
  enable = true;

  # Core LazyVim dependencies (git, ripgrep, fd, etc.)
  installCoreDependencies = true;  # default: true

  extras = {
    lang.typescript = {
      enable = true;
      installDependencies = false;        # Skip typescript tools
      installRuntimeDependencies = true;  # But install nodejs
    };
  };
};
```

**Note:** Dependencies are opt-in per language. Set to `false` to manage packages manually via `extraPackages`.

**⚠️ Experimental:** Automatic dependency installation is experimental and might not cover all required packages. Use `extraPackages` for missing dependencies.

### Custom Configuration

#### Option 1: Inline Configuration

```nix
programs.lazyvim = {
  enable = true;

  config = {
    options = ''
      vim.opt.relativenumber = false
      vim.opt.wrap = true
    '';

    keymaps = ''
      vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", { desc = "Save" })
    '';
  };

  plugins = {
    colorscheme = ''
      return {
        "catppuccin/nvim",
        opts = { flavour = "mocha" },
      }
    '';
  };
};
```

Plugin specs can also be written as Nix attrsets instead of Lua strings, using the `lazyConfig` helper from the flake's `lib` output:

```nix
programs.lazyvim.plugins = {
  colorscheme = inputs.lazyvim-nix.lib.lazyConfig {
    plugin = "catppuccin/nvim";
    opts = { flavour = "mocha"; };
  };

  # A list generates multiple specs in one file; embed Lua code
  # (e.g. functions) with lib.generators.mkLuaInline from nixpkgs
  editor = inputs.lazyvim-nix.lib.lazyConfig [
    { plugin = "neovim/nvim-lspconfig"; opts.servers.nixd = { }; }
    { plugin = "folke/noice.nvim";
      opts.routes = lib.generators.mkLuaInline "function() return my_routes end"; }
  ];
};
```

This works anywhere a Lua string is expected, including extras `config` overrides.

#### Option 2: File-based Configuration

For larger configurations, you can organize your LazyVim config files in a directory:

```nix
programs.lazyvim = {
  enable = true;
  configFiles = ./my-lazyvim-config;
};
```

Directory structure:
```
my-lazyvim-config/
├── config/
│   ├── keymaps.lua
│   ├── options.lua
│   └── autocmds.lua
└── plugins/
    ├── colorscheme.lua
    ├── lsp-config.lua
    └── editor.lua
```

**Note:** You can mix `configFiles` with inline `config` and `plugins` options, but you cannot configure the same file in both places. For example, if `configFiles` contains `config/keymaps.lua`, you cannot also set `config.keymaps`.

## Key Features

- 🚀 **Always up-to-date** - Automatically tracks LazyVim releases with latest plugin versions
- ✅ **Zero-configuration setup** - Just enable and go
- 🤖 **Reproducible builds** - Core and Extra LazyVim plugins locked and in dev mode.

## Documentation

📖 **[Getting Started](https://github.com/pfassina/lazyvim-nix/wiki/Getting-Started)** - Complete setup guide

⚙️ **[Configuration Reference](https://github.com/pfassina/lazyvim-nix/wiki/Configuration-Reference)** - Module options and configuration

🎯 **[LazyVim Extras](https://github.com/pfassina/lazyvim-nix/wiki/LazyVim-Extras)** - Language and feature support

🔧 **[Plugin Sourcing Strategy](https://github.com/pfassina/lazyvim-nix/wiki/Plugin-Sourcing-Strategy)** - How plugins are resolved and managed

🚨 **[Troubleshooting](https://github.com/pfassina/lazyvim-nix/wiki/Troubleshooting)** - Common issues and solutions

## Updating

```bash
nix flake update          # Update to latest LazyVim
home-manager switch       # Apply changes
```

## Acknowledgments

- [LazyVim](https://github.com/LazyVim/LazyVim) by [@folke](https://github.com/folke)
- Inspired by [@azuwis](https://github.com/azuwis)'s Nix setup

## License

MIT
