# Data loading utilities for LazyVim Nix module
{ lib, pkgs }:

{
  # Load plugin data and mappings
  pluginData = pkgs.lazyvimPluginData or (builtins.fromJSON (builtins.readFile ../../data/plugins.json));
  pluginMappings = pkgs.lazyvimPluginMappings or (builtins.fromJSON (builtins.readFile ../../data/mappings.json));

  # Load extras metadata
  extrasMetadata = pkgs.lazyvimExtrasMetadata or (builtins.fromJSON (builtins.readFile ../../data/extras.json));

  # Load treesitter parser mappings
  treesitterMappings = pkgs.lazyvimTreesitterMappings or (builtins.fromJSON (builtins.readFile ../../data/treesitter.json));

  # Load consolidated dependencies
  dependencies = pkgs.lazyvimDependencies or (builtins.fromJSON (builtins.readFile ../../data/dependencies.json));

  # Helper to extract language name from treesitter parser packages
  extractLang = pkg:
    let
      pname = pkg.pname or "";
      # Remove "tree-sitter-" prefix if present (for tree-sitter-grammars)
      withoutPrefix = if lib.hasPrefix "tree-sitter-" pname then
        lib.removePrefix "tree-sitter-" pname
      else
        pname;
    in
      # Also remove "-grammar" suffix if present (tree-sitter-grammars use pnames like "tree-sitter-css-grammar")
      if lib.hasSuffix "-grammar" withoutPrefix then
        lib.removeSuffix "-grammar" withoutPrefix
      else
        withoutPrefix;
}