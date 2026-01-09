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

  # Load LazyVim starter configuration (raw lua content and version)
  starterLua = builtins.readFile ../../data/starter-lazy.lua;
  starterVersion = lib.trim (builtins.readFile ../../data/starter-version.txt);

  # Helper to extract language name from treesitter parser packages
  # Supports:
  #   - pkgs.vimPlugins.nvim-treesitter.grammarPlugins.* (has grammarName)
  #   - pkgs.vimPlugins.nvim-treesitter-parsers.* (alias for above)
  #   - pkgs.vimPlugins.nvim-treesitter.allGrammars (has language + passthru.associatedQuery)
  # Deprecated (throws error):
  #   - pkgs.tree-sitter-grammars.* (use nvim-treesitter-parsers instead)
  extractLang = pkg:
    let
      grammarName = pkg.grammarName or null;
      language = pkg.language or null;
      pname = pkg.pname or "";
      name = pkg.name or "";
      # nvim-treesitter grammars have associatedQuery in passthru
      hasAssociatedQuery = (pkg.passthru or {}) ? associatedQuery;
      isTreeSitterGrammar = lib.hasPrefix "tree-sitter-" pname;
    in
      # Prefer grammarName (from grammarPlugins / nvim-treesitter-parsers)
      if grammarName != null then grammarName
      # Accept language only if it's from nvim-treesitter (has associatedQuery)
      else if language != null && hasAssociatedQuery then language
      # Detect deprecated tree-sitter-grammars (has language but no associatedQuery)
      else if language != null && isTreeSitterGrammar then
        throw ''
          Deprecated treesitter package detected: ${pname}

          pkgs.tree-sitter-grammars is deprecated for lazyvim-nix.
          Please use pkgs.vimPlugins.nvim-treesitter-parsers instead.

          Example migration:
            Before: treesitterParsers = with pkgs.tree-sitter-grammars; [ tree-sitter-lua tree-sitter-nix ];
            After:  treesitterParsers = with pkgs.vimPlugins.nvim-treesitter-parsers; [ lua nix ];

          nvim-treesitter-parsers provides better Neovim compatibility and more grammars (324 vs 131).
        ''
      # Unknown package format
      else
        throw ''
          Unknown treesitter package format: ${name}

          treesitterParsers expects packages from:
            - pkgs.vimPlugins.nvim-treesitter-parsers.* (recommended)
            - pkgs.vimPlugins.nvim-treesitter.grammarPlugins.*
            - pkgs.vimPlugins.nvim-treesitter.allGrammars

          Example:
            treesitterParsers = with pkgs.vimPlugins.nvim-treesitter-parsers; [ lua nix rust go ];
        '';
}