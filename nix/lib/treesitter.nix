# Treesitter management utilities for LazyVim Nix module
{ lib, pkgs, treesitterMappings, extractLang, ignoreBuildNotifications ? false }:

let
  # Load parser revisions for "latest" strategy (may not exist)
  parserRevisionsPath = ../../data/parser-revisions.json;
  parserRevisionsExists = builtins.pathExists parserRevisionsPath;
  parserRevisions = if parserRevisionsExists
    then builtins.fromJSON (builtins.readFile parserRevisionsPath)
    else { parsers = {}; };

  # Build a single parser from source using tree-sitter.buildGrammar
  buildParserFromSource = parserName:
    let
      spec = parserRevisions.parsers.${parserName} or null;
    in
      if spec == null then
        # Fall back to nixpkgs grammarPlugins if no spec
        pkgs.vimPlugins.nvim-treesitter.grammarPlugins.${parserName} or (
          if ignoreBuildNotifications then null
          else builtins.trace "Warning: treesitter parser '${parserName}' not found in parser-revisions.json or nixpkgs" null
        )
      else
        let
          # Build the grammar from source
          grammar = pkgs.tree-sitter.buildGrammar ({
            language = parserName;
            version = "0.0.0+rev-${builtins.substring 0 7 spec.revision}";
            src = pkgs.fetchgit {
              url = spec.url;
              rev = spec.revision;
              sha256 = spec.sha256;
            };
          } // lib.optionalAttrs (spec.location or null != null) {
            # Some parsers have the grammar in a subdirectory
            location = spec.location;
          });

          # Wrap the grammar as a vim plugin with the parser in the right location
          vimPlugin = pkgs.runCommand "treesitter-grammar-${parserName}" {
            passthru = {
              inherit grammar;
              grammarName = parserName;
            };
          } ''
            mkdir -p $out/parser
            ln -s ${grammar}/parser $out/parser/${parserName}.so
          '';
        in
          vimPlugin;

in {
  # Derive automatic treesitter parsers
  automaticTreesitterParsers = cfg: enabledExtraNames:
    if cfg.enable then
      let
        # Core parsers are always included
        coreParsers = treesitterMappings.core or [];

        # Extra parsers based on enabled extras
        extraParsers = lib.flatten (map (extraName:
          treesitterMappings.extras.${extraName} or []
        ) enabledExtraNames);

        # Combine and deduplicate all parsers (keep as names, not packages)
        allParsers = lib.unique (coreParsers ++ extraParsers ++ (map extractLang cfg.treesitterParsers));
      in
        allParsers
    else
      map extractLang cfg.treesitterParsers;

  # Treesitter configuration - use nvim-treesitter's grammar plugins directly (for "nixpkgs" strategy)
  treesitterGrammars = automaticTreesitterParsers:
    let
      # automaticTreesitterParsers now contains parser names, not packages
      parserNames = automaticTreesitterParsers;

      # Use nvim-treesitter's grammar plugins which are compatible
      parserPackages = lib.filter (pkg: pkg != null) (map (parserName:
        pkgs.vimPlugins.nvim-treesitter.grammarPlugins.${parserName} or (
          if ignoreBuildNotifications then null
          else builtins.trace "Warning: treesitter parser '${parserName}' not found in nvim-treesitter grammar plugins" null
        )
      ) parserNames);

      parsers = pkgs.symlinkJoin {
        name = "treesitter-parsers";
        paths = parserPackages;
      };
    in parsers;

  # Build treesitter grammars from source using parser-revisions.json (for "latest" strategy)
  # This ensures parsers match the nvim-treesitter version specified in plugins.json
  treesitterGrammarsFromSource = automaticTreesitterParsers:
    let
      parserNames = automaticTreesitterParsers;

      # Build parsers from source using parser-revisions.json
      parserPackages = lib.filter (pkg: pkg != null) (map buildParserFromSource parserNames);

      parsers = pkgs.symlinkJoin {
        name = "treesitter-parsers-from-source";
        paths = parserPackages;
      };
    in parsers;

  # Check if parser revisions are available
  hasParserRevisions = parserRevisionsExists && (parserRevisions.parsers or {}) != {};
}
