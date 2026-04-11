# Treesitter management utilities for LazyVim Nix module
{
  lib,
  pkgs,
  treesitterMappings,
  extractLang,
  ignoreBuildNotifications ? false,
}:

let
  parserManifestPath = ../../data/parser-manifest.json;
  parserManifestExists = builtins.pathExists parserManifestPath;
  parserManifest =
    if parserManifestExists then
      builtins.fromJSON (builtins.readFile parserManifestPath)
    else
      { parsers = { }; };

  parserRequires =
    parserName:
    let
      spec = parserManifest.parsers.${parserName} or null;
      requires = if spec == null then [ ] else spec.requires or [ ];
    in
    # Some upstream `requires` entries are query-only namespaces like `html_tags`
    # or `ecma`, not standalone buildable parsers. Only expand dependencies that
    # exist as real manifest-backed parser entries.
    lib.filter (requiredParser: builtins.hasAttr requiredParser parserManifest.parsers) requires;

  expandParserDependencies =
    parserNames:
    let
      go =
        seen: pending:
        if pending == [ ] then
          seen
        else
          let
            parserName = builtins.head pending;
            rest = builtins.tail pending;
          in
          if builtins.elem parserName seen then
            go seen rest
          else
            go (seen ++ [ parserName ]) (rest ++ parserRequires parserName);
    in
    go [ ] parserNames;

  # Build a single parser from source using tree-sitter.buildGrammar
  buildParserFromSource =
    parserName:
    let
      spec = parserManifest.parsers.${parserName} or null;
    in
    if spec == null then
      throw ''
        treesitter parser '${parserName}' is not available in lazyvim-nix's generated parser manifest.

        programs.lazyvim.pluginSource = "latest" requires parser/query coherence and only builds parsers
        from the pinned nvim-treesitter source recorded in data/parser-manifest.json.

        Regenerate the manifest with scripts/update-plugins.sh or switch to programs.lazyvim.pluginSource = "nixpkgs"
        if you explicitly want nixpkgs parser packages instead.
      ''
    else
      let
        # Build the grammar from source
        revShort = builtins.substring 0 7 spec.revision;
        grammar = pkgs.tree-sitter.buildGrammar ({
          language = parserName;
          version = "0.0.0+rev-${revShort}";
          src = pkgs.fetchgit {
            url = spec.url;
            rev = spec.revision;
            sha256 = spec.sha256;
            fetchSubmodules = false;
          };
          # Add tree-sitter + nodejs for grammars that need parser generation
          generate = true;
          # Override configurePhase for cross-nixpkgs compatibility:
          # - nixpkgs 24.11: its configurePhase runs tree-sitter generate
          #   unconditionally, which fails for monorepo grammars whose grammar.js
          #   depends on sibling packages not available in the sandbox (e.g. tsx
          #   depends on tree-sitter-javascript)
          # - nixpkgs unstable: its configurePhase has tree-sitter.json version
          #   checks that fail for pinned-commit builds
          # Subdirectory navigation (cd) replaces the location attribute to avoid
          # conflicts with nixpkgs' setSourceRoot mechanism.
          configurePhase = ''
            runHook preConfigure
            ${lib.optionalString (spec.location or null != null) "cd ${spec.location}"}
            runHook postConfigure
          '';
          # Only generate when src/parser.c is not checked into the repo
          preBuild = ''
            if [[ ! -e src/parser.c ]]; then
              tree-sitter generate
            fi
          '';
        });

        # Wrap the grammar as a vim plugin with the parser in the right location
        vimPlugin =
          pkgs.runCommand "treesitter-grammar-${parserName}"
            {
              passthru = {
                inherit grammar;
                grammarName = parserName;
              };
            }
            ''
              mkdir -p $out/parser
              ln -s ${grammar}/parser $out/parser/${parserName}.so
            '';
      in
      vimPlugin;

in
{
  # Derive automatic treesitter parsers
  automaticTreesitterParsers =
    cfg: enabledExtraNames:
    if cfg.enable then
      let
        # Core parsers are always included
        coreParsers = treesitterMappings.core or [ ];

        # Extra parsers based on enabled extras
        extraParsers = lib.flatten (
          map (extraName: treesitterMappings.extras.${extraName} or [ ]) enabledExtraNames
        );

        requestedParsers = lib.unique (
          coreParsers ++ extraParsers ++ (map extractLang cfg.treesitterParsers)
        );
      in
      expandParserDependencies requestedParsers
    else
      expandParserDependencies (map extractLang cfg.treesitterParsers);

  # Treesitter configuration - use nvim-treesitter's grammar plugins directly (for "nixpkgs" strategy)
  treesitterGrammars =
    automaticTreesitterParsers:
    let
      # automaticTreesitterParsers now contains parser names, not packages
      parserNames = automaticTreesitterParsers;

      # Use nvim-treesitter's grammar plugins which are compatible
      parserPackages = lib.filter (pkg: pkg != null) (
        map (
          parserName:
          pkgs.vimPlugins.nvim-treesitter.grammarPlugins.${parserName} or (
            if ignoreBuildNotifications then
              null
            else
              builtins.trace "Warning: treesitter parser '${parserName}' not found in nvim-treesitter grammar plugins" null
          )
        ) parserNames
      );

      parsers = pkgs.symlinkJoin {
        name = "treesitter-parsers";
        paths = parserPackages;
      };
    in
    parsers;

  # Build treesitter grammars from source using parser-manifest.json (for "latest" strategy)
  # This ensures parsers match the nvim-treesitter version specified in plugins.json
  treesitterGrammarsFromSource =
    automaticTreesitterParsers:
    let
      parserNames = automaticTreesitterParsers;
      missingParsers = lib.filter (
        parserName: !(builtins.hasAttr parserName parserManifest.parsers)
      ) parserNames;

      _ =
        if missingParsers != [ ] then
          throw ''
            lazyvim-nix could not build the following treesitter parsers from the generated parser manifest:
              ${lib.concatStringsSep ", " missingParsers}

            programs.lazyvim.pluginSource = "latest" only uses parsers recorded in data/parser-manifest.json
            so queries and parsers stay aligned to the same pinned nvim-treesitter source.

            Regenerate the manifest with scripts/update-plugins.sh or switch to programs.lazyvim.pluginSource = "nixpkgs"
            if you explicitly want nixpkgs parser packages instead.
          ''
        else
          null;

      # Build parsers from source using parser-manifest.json
      parserPackages = lib.filter (pkg: pkg != null) (map buildParserFromSource parserNames);

      parsers = builtins.seq _ (
        pkgs.symlinkJoin {
          name = "treesitter-parsers-from-source";
          paths = parserPackages;
        }
      );
    in
    parsers;

  # Check if parser manifest is available
  hasParserManifest = parserManifestExists && (parserManifest.parsers or { }) != { };

  inherit expandParserDependencies;
}
