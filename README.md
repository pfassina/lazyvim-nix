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

## Basic Configuration

### Language Support

```nix
programs.lazyvim = {
  enable = true;

  extras = {
    lang.nix.enable = true;
    lang.python.enable = true;
  };

  # Required for syntax highlighting
  treesitterParsers = with pkgs.tree-sitter-grammars; [
    tree-sitter-nix
    tree-sitter-python
  ];

  # Language servers, formatters, linters (since Mason is disabled)
  extraPackages = with pkgs; [
    nixd       # Nix LSP
    pyright    # Python LSP
    alejandra  # Nix formatter
  ];
};
```

**Note:** LazyVim extras install Neovim plugins (LSP configs, syntax highlighting) but NOT the actual language tools (LSP servers, formatters, linters). You must provide these via `extraPackages`.

### Custom Configuration

```nix
programs.lazyvim = {
  enable = true;

  pluginFiles = ./lua/plugins;

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

The optional `pluginFiles` directory lets you keep regular Lua plugin files (e.g. `./lua/plugins/*.lua`).
Each `.lua` file is linked into `~/.config/nvim/lua/plugins/`, and if a filename conflicts with an inline
`plugins` entry, the real file takes precedence with a warning at evaluation time.

## Key Features

- 🚀 **Always up-to-date** - Automatically tracks LazyVim releases with latest plugin versions
- ✅ **Zero-configuration setup** - Just enable and go
- 🤖 **Reproducible builds** - All plugins managed through Nix

## Documentation

📖 **[Getting Started](https://github.com/pfassina/lazyvim-nix/wiki/Getting-Started)** - Complete setup guide

⚙️ **[Configuration Reference](https://github.com/pfassina/lazyvim-nix/wiki/Configuration-Reference)** - All available options

🎯 **[LazyVim Extras](https://github.com/pfassina/lazyvim-nix/wiki/LazyVim-Extras)** - Language and feature support

🏗️ **[Architecture](https://github.com/pfassina/lazyvim-nix/wiki/Architecture-and-How-It-Works)** - How it works under the hood

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
