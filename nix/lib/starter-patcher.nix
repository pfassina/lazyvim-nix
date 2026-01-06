# Starter patcher - applies Nix-specific modifications to the LazyVim starter config
# This approach preserves upstream improvements while injecting necessary Nix overrides
{ lib }:

let
  # The spec content that replaces the upstream spec section
  # This includes all Nix-specific plugin configurations
  nixSpecContent = { devPath, extrasImportSpecs, availableDevSpecs, treesitterSpec }:
    ''
  spec = {
    -- [NIX] LazyVim with dev mode for Nix-managed packages
    { "LazyVim/LazyVim", import = "lazyvim.plugins", dev = true, pin = true },
    -- [NIX] LazyVim extras
    ${lib.concatStringsSep "\n    " extrasImportSpecs}
    -- [NIX] Mason disabled - Nix provides tools via extraPackages
    { "mason-org/mason.nvim", enabled = false },
    { "mason-org/mason-lspconfig.nvim", enabled = false },
    { "jay-babu/mason-nvim-dap.nvim", enabled = false },
    -- [NIX] Treesitter configured for Nix-managed parsers
    ${treesitterSpec}
    -- [NIX] Available plugins marked as dev (Nix-managed)
    ${lib.concatStringsSep "\n    " availableDevSpecs}
    -- User plugins
    { import = "plugins" },
  },
  -- [NIX] Dev path for Nix-symlinked plugins
  dev = {
    path = "${devPath}",
    patterns = {},  -- Don't automatically match, use explicit dev = true
    fallback = false,
  },'';

  # The treesitter spec for Nix-managed parsers
  defaultTreesitterSpec = ''
{
      "nvim-treesitter/nvim-treesitter",
      event = { "BufReadPost", "BufNewFile", "BufWritePre", "VeryLazy" },
      cmd = { "TSUpdate", "TSInstall", "TSLog", "TSUninstall" },
      -- [NIX] Parser compilation is skipped when using Nix
      build = false,
      opts = {
        auto_install = false,
        ensure_installed = {},
        highlight = { enable = true },
        indent = { enable = true },
        incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = "<C-space>",
            node_incremental = "<C-space>",
            scope_incremental = false,
            node_decremental = "<bs>",
          },
        },
      },
      dev = true,
      pin = true,
    },'';

  # Patterns to find in the starter config
  # These must match EXACTLY what's in the upstream starter (2-space indentation)
  upstreamSpecPattern = "  spec = {\n    -- add LazyVim and import its plugins\n    { \"LazyVim/LazyVim\", import = \"lazyvim.plugins\" },\n    -- import/override with your plugins\n    { import = \"plugins\" },\n  },";

  upstreamCheckerPattern = "  checker = {\n    enabled = true, -- check for plugin updates periodically\n    notify = false, -- notify on update\n  }, -- automatically check for plugin updates";

  nixCheckerReplacement = "  checker = {\n    enabled = false, -- [NIX] Disabled - Nix manages plugin versions\n    notify = false,\n  },\n  -- [NIX] Disable config change notifications since Nix generates config\n  change_detection = { notify = false },";

in {
  # Main patching function
  # Takes the raw starter lua content and applies Nix-specific patches
  patchStarterConfig = {
    starterLua,
    devPath,
    extrasImportSpecs,
    availableDevSpecs,
    treesitterSpec ? defaultTreesitterSpec,
    starterVersion ? "unknown"
  }:
    let
      # Build the Nix spec replacement
      nixSpec = nixSpecContent {
        inherit devPath extrasImportSpecs availableDevSpecs treesitterSpec;
      };

      # Step 1: Replace the spec section with Nix-specific content
      withNixSpec = builtins.replaceStrings
        [ upstreamSpecPattern ]
        [ nixSpec ]
        starterLua;

      # Step 2: Replace checker and add change_detection
      withNixChecker = builtins.replaceStrings
        [ upstreamCheckerPattern ]
        [ nixCheckerReplacement ]
        withNixSpec;

      # Verify patches were applied (the original patterns should no longer exist)
      specPatched = !lib.hasInfix "-- add LazyVim and import its plugins" withNixChecker;
      checkerPatched = !lib.hasInfix "enabled = true, -- check for plugin updates periodically" withNixChecker;

      # Build the final config with header comment
      patchedConfig = ''
        -- LazyVim Nix Configuration
        -- Based on LazyVim/starter (commit: ${starterVersion})
        -- Patched for Nix compatibility by lazyvim-nix flake
        -- Sections marked [NIX] are Nix-specific modifications

        ${withNixChecker}'';

    in
      # Assert that patches were applied successfully
      if !specPatched then
        builtins.throw ''
          ERROR: Failed to patch LazyVim starter spec section.
          The upstream starter structure may have changed.
          Expected pattern not found: "-- add LazyVim and import its plugins"
          Please review data/starter-lazy.lua and update nix/lib/starter-patcher.nix
        ''
      else if !checkerPatched then
        builtins.throw ''
          ERROR: Failed to patch LazyVim starter checker section.
          The upstream starter structure may have changed.
          Expected pattern not found: "enabled = true, -- check for plugin updates periodically"
          Please review data/starter-lazy.lua and update nix/lib/starter-patcher.nix
        ''
      else
        patchedConfig;

  # Export the default treesitter spec for use by config-generation.nix
  inherit defaultTreesitterSpec;
}
