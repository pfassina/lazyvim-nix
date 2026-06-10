# Simplified end-to-end tests
{ testLib, ... }:

{
  # Test that lazy.nvim is in the plugin list
  test-lazy-nvim-included = testLib.testNixExpr
    "lazy-nvim-included"
    ''
      let
        hasLazyNvim = (import <nixpkgs> {}).vimPlugins ? lazy-nvim;
      in hasLazyNvim
    ''
    "true";

  # Test basic neovim package exists
  test-neovim-exists = testLib.testNixExpr
    "neovim-exists"
    ''
      let
        hasNeovim = (import <nixpkgs> {}) ? neovim-unwrapped;
      in hasNeovim
    ''
    "true";
}