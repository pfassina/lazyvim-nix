# Nix-specific overrides for LazyVim plugins
{...}: {
  # Mason is completely disabled in Nix (essential for Nix compatibility)
  "mason.nvim" = {
    enabled = false;
  };

  "mason-lspconfig.nvim" = {
    enabled = false;
  };

  "mason-nvim-dap.nvim" = {
    enabled = false;
  };
}
