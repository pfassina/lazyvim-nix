# Unit tests for treesitter parser resolution
# Imports the real nix/lib/treesitter.nix and nix/lib/data-loading.nix and
# verifies parser derivation, dependency expansion, and extractLang behavior.
{ pkgs, testLib, moduleUnderTest }:

let
  lib = pkgs.lib;

  # The real data loading library (provides extractLang)
  dataLib = import ../../nix/lib/data-loading.nix { inherit lib pkgs; };
  inherit (dataLib) extractLang;

  # Fixture treesitter mappings (shape of data/treesitter.json)
  fixtureTreesitterMappings = {
    core = [ "lua" "vim" "query" ];
    extras = {
      "lang.rust" = [ "rust" "ron" ];
      "lang.go" = [ "go" "gomod" ];
      "lang.typescript" = [ ]; # Extras may add no parsers
    };
  };

  # The real treesitter library under test
  tsLib = import ../../nix/lib/treesitter.nix {
    inherit lib pkgs;
    treesitterMappings = fixtureTreesitterMappings;
    inherit extractLang;
    ignoreBuildNotifications = true;
  };

  inherit (tsLib) automaticTreesitterParsers expandParserDependencies
    treesitterGrammars treesitterGrammarsFromSource hasParserManifest;

  baseCfg = {
    enable = true;
    treesitterParsers = [ ];
  };

  coreOnlyParsers = automaticTreesitterParsers baseCfg [ ];

  # Real shipped parser manifest (used by expandParserDependencies)
  parserManifest = builtins.fromJSON (builtins.readFile ../../data/parser-manifest.json);

in {
  # Core parsers are always included
  test-core-parsers-always-included = testLib.testEval
    "core-parsers-always-included"
    (builtins.all (p: builtins.elem p coreOnlyParsers) fixtureTreesitterMappings.core)
    true;

  # Enabled extras add their parsers
  test-enabled-extras-add-parsers = testLib.testEval
    "enabled-extras-add-parsers"
    (let parsers = automaticTreesitterParsers baseCfg [ "lang.rust" ];
     in builtins.elem "rust" parsers && builtins.elem "ron" parsers)
    true;

  # Extras that are not enabled contribute no parsers
  test-disabled-extras-no-parsers = testLib.testEval
    "disabled-extras-no-parsers"
    (builtins.elem "rust" coreOnlyParsers)
    false;

  # Extras with an empty parser list change nothing
  test-extras-no-additional-parsers = testLib.testEval
    "extras-no-additional-parsers"
    (automaticTreesitterParsers baseCfg [ "lang.typescript" ] == coreOnlyParsers)
    true;

  # Multiple enabled extras all contribute parsers
  test-multiple-extras-enabled = testLib.testEval
    "multiple-extras-enabled"
    (let parsers = automaticTreesitterParsers baseCfg [ "lang.rust" "lang.go" ];
     in builtins.all (p: builtins.elem p parsers) [ "rust" "ron" "go" "gomod" ])
    true;

  # Manual treesitterParsers packages are merged via extractLang
  test-manual-parsers-merged = testLib.testEval
    "manual-parsers-merged"
    (builtins.elem "wgsl" (automaticTreesitterParsers (baseCfg // {
      treesitterParsers = [ { grammarName = "wgsl"; } ];
    }) [ ]))
    true;

  # A manual parser already in core is deduplicated
  test-parser-deduplication = testLib.testEval
    "parser-deduplication"
    (builtins.length (lib.filter (p: p == "lua") (automaticTreesitterParsers (baseCfg // {
      treesitterParsers = [ { grammarName = "lua"; } ];
    }) [ ])))
    1;

  # With the module disabled, only manual parsers are derived
  test-disabled-module-only-manual-parsers = testLib.testEval
    "disabled-module-only-manual-parsers"
    (let parsers = automaticTreesitterParsers {
       enable = false;
       treesitterParsers = [ { grammarName = "wgsl"; } ];
     } [ "lang.rust" ];
     in builtins.elem "wgsl" parsers && !(builtins.elem "lua" parsers) && !(builtins.elem "rust" parsers))
    true;

  # expandParserDependencies: transitive requires from the real manifest are
  # pulled in (xml requires dtd)
  test-parser-dependency-closure-includes-transitive-requires = testLib.testEval
    "parser-dependency-closure-includes-transitive-requires"
    (builtins.elem "dtd" (expandParserDependencies [ "xml" ]))
    true;

  # expandParserDependencies: shared dependencies appear exactly once
  test-parser-dependency-closure-deduplicates-shared-deps = testLib.testEval
    "parser-dependency-closure-deduplicates-shared-deps"
    (builtins.length (lib.filter (p: p == "dtd") (expandParserDependencies [ "xml" "dtd" ])))
    1;

  # expandParserDependencies: query-only namespaces (html_tags) that are not
  # real manifest parsers are not pulled in
  test-parser-dependency-closure-skips-non-manifest-requires = testLib.testEval
    "parser-dependency-closure-skips-non-manifest-requires"
    (builtins.elem "html_tags" (expandParserDependencies [ "html" ]))
    false;

  # treesitterGrammars ("nixpkgs" strategy): produces a parser derivation
  test-treesitter-grammars-is-derivation = testLib.testEval
    "treesitter-grammars-is-derivation"
    (lib.isDerivation (treesitterGrammars [ "lua" ]))
    true;

  # treesitterGrammarsFromSource ("latest" strategy): a parser missing from
  # the manifest fails with a clear error instead of building silently
  test-treesitter-from-source-missing-parser-throws = testLib.testEval
    "treesitter-from-source-missing-parser-throws"
    (builtins.tryEval (treesitterGrammarsFromSource [ "definitely_missing_parser" ])).success
    false;

  # The shipped parser manifest is detected as available
  test-has-parser-manifest = testLib.testEval
    "has-parser-manifest"
    hasParserManifest
    true;

  # extractLang: grammarPlugins / nvim-treesitter-parsers style (grammarName)
  test-extract-lang-grammar-plugins = testLib.testEval
    "extract-lang-grammar-plugins"
    (map extractLang [
      { grammarName = "rust"; }
      { grammarName = "c_sharp"; }
      { grammarName = "json5"; }
    ] == [ "rust" "c_sharp" "json5" ])
    true;

  # extractLang: allGrammars style (language + passthru.associatedQuery)
  test-extract-lang-all-grammars = testLib.testEval
    "extract-lang-all-grammars"
    (map extractLang [
      { language = "ada"; pname = "tree-sitter-ada"; passthru.associatedQuery = { }; }
      { language = "markdown_inline"; pname = "tree-sitter-markdown_inline"; passthru.associatedQuery = { }; }
    ] == [ "ada" "markdown_inline" ])
    true;

  # extractLang: grammarName takes priority over language
  test-extract-lang-grammarname-priority = testLib.testEval
    "extract-lang-grammarname-priority"
    (extractLang { grammarName = "correct"; language = "wrong"; passthru.associatedQuery = { }; })
    "correct";

  # extractLang: deprecated tree-sitter-grammars packages (language but no
  # associatedQuery) throw a migration error
  test-extract-lang-deprecated-throws = testLib.testEval
    "extract-lang-deprecated-throws"
    (builtins.tryEval (extractLang {
      language = "rust";
      pname = "tree-sitter-rust";
      name = "tree-sitter-rust";
    })).success
    false;

  # extractLang: unknown package formats throw
  test-extract-lang-unknown-throws = testLib.testEval
    "extract-lang-unknown-throws"
    (builtins.tryEval (extractLang { name = "mystery-package"; })).success
    false;

  # Shipped parser manifest sanity: covers runtime languages and preserves
  # the requires metadata that dependency expansion relies on
  test-parser-manifest-covers-runtime-languages = testLib.testEval
    "parser-manifest-covers-runtime-languages"
    (parserManifest.parsers ? make &&
     parserManifest.parsers ? gotmpl &&
     parserManifest.parsers ? xml &&
     parserManifest.parsers ? dtd)
    true;

  test-parser-manifest-preserves-requires = testLib.testEval
    "parser-manifest-preserves-requires"
    (parserManifest.parsers.xml.requires or [ ] == [ "dtd" ])
    true;
}
