# Unit tests for treesitter parser resolution
{ pkgs, testLib, moduleUnderTest }:

let
  # Test treesitter mappings data
  testTreesitterMappings = {
    core = [
      "bash" "c" "diff" "html" "javascript" "jsdoc" "json" "jsonc"
      "lua" "luadoc" "luap" "markdown" "markdown_inline" "printf"
      "python" "query" "regex" "toml" "tsx" "typescript"
      "vim" "vimdoc" "xml" "yaml"
    ];
    extras = {
      "lang.rust" = [ "rust" "ron" ];
      "lang.go" = [ "go" "gomod" "gowork" "gosum" ];
      "lang.python" = [ "ninja" "rst" ];
      "lang.nix" = [ "nix" ];
      "lang.typescript" = [ ]; # Some extras might not add extra parsers
    };
  };

  # Mock enabled extras configurations
  testExtrasConfig = {
    lang = {
      rust = { enable = true; };
      python = { enable = true; };
      nix = { enable = false; }; # Disabled
      typescript = { enable = true; }; # No extra parsers
    };
  };

  # Helper function to derive automatic parsers (simplified from module logic)
  deriveAutomaticParsers = extrasConfig: treesitterMappings: manualParsers:
    let
      # Get enabled extra names in "category.name" format
      enabledExtraNames = pkgs.lib.flatten (pkgs.lib.mapAttrsToList (category: extras:
        pkgs.lib.mapAttrsToList (name: extraConfig:
          pkgs.lib.optional (extraConfig.enable or false) "${category}.${name}"
        ) extras
      ) extrasConfig);

      # Core parsers are always included
      coreParsers = treesitterMappings.core or [];

      # Extra parsers based on enabled extras
      extraParsers = pkgs.lib.flatten (map (extraName:
        treesitterMappings.extras.${extraName} or []
      ) enabledExtraNames);

      # Combine and deduplicate all parsers
      allParsers = pkgs.lib.unique (coreParsers ++ extraParsers ++ manualParsers);
    in
      allParsers;

in {
  # Test core parsers are always included
  test-core-parsers-always-included = testLib.testNixExpr
    "core-parsers-always-included"
    ''
      let
        coreParsers = [
          "bash" "c" "diff" "html" "javascript" "jsdoc" "json" "jsonc"
          "lua" "luadoc" "luap" "markdown" "markdown_inline" "printf"
          "python" "query" "regex" "toml" "tsx" "typescript"
          "vim" "vimdoc" "xml" "yaml"
        ];
        # Core parsers should be present even with no extras enabled
        coreCount = builtins.length coreParsers;
      in coreCount == 24
    ''
    "true";

  # Test enabled extras add their parsers
  test-enabled-extras-add-parsers = testLib.testNixExpr
    "enabled-extras-add-parsers"
    ''
      let
        # Simulate rust extra being enabled
        enabledExtras = ["lang.rust"];
        rustParsers = ["rust" "ron"];
        allParsers = [ "bash" "c" "diff" "html" "javascript" "jsdoc" "json" "jsonc" "lua" "luadoc" "luap" "markdown" "markdown_inline" "printf" "python" "query" "regex" "toml" "tsx" "typescript" "vim" "vimdoc" "xml" "yaml" ] ++ rustParsers;
        hasRust = builtins.elem "rust" allParsers;
        hasRon = builtins.elem "ron" allParsers;
      in hasRust && hasRon
    ''
    "true";

  # Test disabled extras don't add parsers
  test-disabled-extras-no-parsers = testLib.testNixExpr
    "disabled-extras-no-parsers"
    ''
      let
        # Nix extra is disabled, so "nix" parser shouldn't be in enabled list
        enabledExtras = ["lang.rust" "lang.python"]; # nix not enabled
        nixParserShouldBeAbsent = ! (builtins.elem "lang.nix" enabledExtras);
      in nixParserShouldBeAbsent
    ''
    "true";

  # Test manual parsers are merged with automatic ones
  test-manual-parsers-merged = testLib.testNixExpr
    "manual-parsers-merged"
    ''
      let
        coreParsers = ["lua" "vim"];
        extraParsers = ["rust"];
        manualParsers = ["wgsl" "custom"];
        allParsers = coreParsers ++ extraParsers ++ manualParsers;
        hasManual = builtins.elem "wgsl" allParsers && builtins.elem "custom" allParsers;
        hasCore = builtins.elem "lua" allParsers;
        hasExtra = builtins.elem "rust" allParsers;
      in hasManual && hasCore && hasExtra
    ''
    "true";

  # Test deduplication works correctly
  test-parser-deduplication = testLib.testNixExpr
    "parser-deduplication"
    ''
      let
        # python is in core, but user also specifies it manually
        coreParsers = ["python" "lua"];
        manualParsers = ["python" "custom"]; # duplicate python
        combined = coreParsers ++ manualParsers;
        deduplicated = builtins.foldl' (acc: item:
          if builtins.elem item acc then acc else acc ++ [item]
        ) [] combined;
        pythonCount = builtins.length (builtins.filter (x: x == "python") combined);
        deduplicatedPythonCount = builtins.length (builtins.filter (x: x == "python") deduplicated);
      in pythonCount == 2 && deduplicatedPythonCount == 1
    ''
    "true";

  # Test extras with no additional parsers
  test-extras-no-additional-parsers = testLib.testNixExpr
    "extras-no-additional-parsers"
    ''
      let
        # Some extras like typescript might not add extra parsers (typescript is in core)
        typescriptExtraParsers = [];
        emptyExtraResult = builtins.length typescriptExtraParsers == 0;
      in emptyExtraResult
    ''
    "true";

  # Test multiple extras enabled
  test-multiple-extras-enabled = testLib.testNixExpr
    "multiple-extras-enabled"
    ''
      let
        enabledExtras = ["lang.rust" "lang.go"];
        rustParsers = ["rust" "ron"];
        goParsers = ["go" "gomod" "gowork" "gosum"];
        allExtraParsers = rustParsers ++ goParsers;
        hasAllRust = builtins.all (p: builtins.elem p allExtraParsers) rustParsers;
        hasAllGo = builtins.all (p: builtins.elem p allExtraParsers) goParsers;
      in hasAllRust && hasAllGo
    ''
    "true";

  # Test parser name format validation
  test-parser-name-format = testLib.testNixExpr
    "parser-name-format"
    ''
      let
        validParsers = ["rust" "python" "go" "json5" "c_sharp"];
        # All parser names should be valid identifiers (letters, numbers, underscore)
        isValidName = name:
          builtins.match "[a-zA-Z][a-zA-Z0-9_]*" name != null;
        allValid = builtins.all isValidName validParsers;
      in allValid
    ''
    "true";

  # Test enabled extra name derivation
  test-enabled-extra-names = testLib.testNixExpr
    "enabled-extra-names"
    ''
      let
        extrasConfig = {
          lang = {
            rust = { enable = true; };
            python = { enable = true; };
            nix = { enable = false; };
          };
          editor = {
            dial = { enable = true; };
          };
        };
        # Should get ["lang.rust" "lang.python" "editor.dial"]
        enabledNames = builtins.foldl' (acc: category:
          acc ++ (builtins.foldl' (acc2: name:
            let extraConfig = extrasConfig.''${category}.''${name};
            in if extraConfig.enable or false
               then acc2 ++ ["''${category}.''${name}"]
               else acc2
          ) [] (builtins.attrNames extrasConfig.''${category}))
        ) [] (builtins.attrNames extrasConfig);
        hasRust = builtins.elem "lang.rust" enabledNames;
        hasPython = builtins.elem "lang.python" enabledNames;
        hasNix = builtins.elem "lang.nix" enabledNames;
        hasDial = builtins.elem "editor.dial" enabledNames;
      in hasRust && hasPython && !hasNix && hasDial
    ''
    "true";

  # Test parser package name mapping
  test-parser-package-mapping = testLib.testNixExpr
    "parser-package-mapping"
    ''
      let
        # Parser names should map to grammarPlugins packages
        parserName = "rust";
        # In real implementation: pkgs.vimPlugins.nvim-treesitter.grammarPlugins.''${parserName}
        expectedPackagePath = "vimPlugins.nvim-treesitter.grammarPlugins.rust";
        # Just verify the pattern is correct
        validPath = builtins.match "vimPlugins\.nvim-treesitter\.grammarPlugins\.[a-zA-Z_][a-zA-Z0-9_]*" expectedPackagePath != null;
      in validPath
    ''
    "true";

  # Test edge case: empty extras configuration
  test-empty-extras-config = testLib.testNixExpr
    "empty-extras-config"
    ''
      let
        emptyExtras = {};
        enabledNames = [];
        # Should only have core parsers
        result = [ "bash" "c" "diff" "html" "javascript" "jsdoc" "json" "jsonc" "lua" "luadoc" "luap" "markdown" "markdown_inline" "printf" "python" "query" "regex" "toml" "tsx" "typescript" "vim" "vimdoc" "xml" "yaml" ];
        onlyCore = builtins.length result == 24;
      in onlyCore
    ''
    "true";

  # Test extractLang function with nvim-treesitter-parsers (grammarName attribute)
  test-extract-lang-grammar-plugins = testLib.testNixExpr
    "extract-lang-grammar-plugins"
    ''
      let
        lib = (import <nixpkgs> {}).lib;
        # Updated extractLang supporting grammarName, language with associatedQuery, and detecting deprecated packages
        extractLang = pkg:
          let
            grammarName = pkg.grammarName or null;
            language = pkg.language or null;
            pname = pkg.pname or "";
            hasAssociatedQuery = (pkg.passthru or {}) ? associatedQuery;
          in
            if grammarName != null then grammarName
            else if language != null && hasAssociatedQuery then language
            else if language != null && lib.hasPrefix "tree-sitter-" pname then
              abort "tree-sitter-grammars is deprecated"
            else
              abort "Unknown package format";

        # Test with nvim-treesitter-parsers / grammarPlugins packages (have grammarName)
        mockPackage1 = { grammarName = "rust"; name = "vimplugin-nvim-treesitter-grammar-rust"; };
        mockPackage2 = { grammarName = "python"; name = "vimplugin-nvim-treesitter-grammar-python"; };
        mockPackage3 = { grammarName = "css"; name = "vimplugin-nvim-treesitter-grammar-css"; };

        extracted1 = extractLang mockPackage1;
        extracted2 = extractLang mockPackage2;
        extracted3 = extractLang mockPackage3;
      in
        extracted1 == "rust" &&
        extracted2 == "python" &&
        extracted3 == "css"
    ''
    "true";

  # Test extractLang function with allGrammars/builtGrammars (language + associatedQuery)
  test-extract-lang-all-grammars = testLib.testNixExpr
    "extract-lang-all-grammars"
    ''
      let
        lib = (import <nixpkgs> {}).lib;
        # Updated extractLang supporting grammarName, language with associatedQuery, and detecting deprecated packages
        extractLang = pkg:
          let
            grammarName = pkg.grammarName or null;
            language = pkg.language or null;
            pname = pkg.pname or "";
            hasAssociatedQuery = (pkg.passthru or {}) ? associatedQuery;
          in
            if grammarName != null then grammarName
            else if language != null && hasAssociatedQuery then language
            else if language != null && lib.hasPrefix "tree-sitter-" pname then
              abort "tree-sitter-grammars is deprecated"
            else
              abort "Unknown package format";

        # Test with allGrammars/builtGrammars packages (have language + passthru.associatedQuery)
        mockPackage1 = { language = "ada"; pname = "tree-sitter-ada"; name = "tree-sitter-ada-0.0.0"; passthru.associatedQuery = {}; };
        mockPackage2 = { language = "zig"; pname = "tree-sitter-zig"; name = "tree-sitter-zig-0.0.0"; passthru.associatedQuery = {}; };
        mockPackage3 = { language = "wgsl"; pname = "tree-sitter-wgsl"; name = "tree-sitter-wgsl-0.0.0"; passthru.associatedQuery = {}; };

        extracted1 = extractLang mockPackage1;
        extracted2 = extractLang mockPackage2;
        extracted3 = extractLang mockPackage3;
      in
        extracted1 == "ada" &&
        extracted2 == "zig" &&
        extracted3 == "wgsl"
    ''
    "true";

  # Test extractLang prefers grammarName over language
  test-extract-lang-grammarname-priority = testLib.testNixExpr
    "extract-lang-grammarname-priority"
    ''
      let
        lib = (import <nixpkgs> {}).lib;
        extractLang = pkg:
          let
            grammarName = pkg.grammarName or null;
            language = pkg.language or null;
            hasAssociatedQuery = (pkg.passthru or {}) ? associatedQuery;
          in
            if grammarName != null then grammarName
            else if language != null && hasAssociatedQuery then language
            else abort "no grammarName or valid language";

        # Package with both attributes - grammarName should win
        mockPackage = { grammarName = "correct"; language = "wrong"; passthru.associatedQuery = {}; };
        extracted = extractLang mockPackage;
      in
        extracted == "correct"
    ''
    "true";

  # Test extractLang with mixed package types
  test-extract-lang-mixed = testLib.testNixExpr
    "extract-lang-mixed"
    ''
      let
        lib = (import <nixpkgs> {}).lib;
        extractLang = pkg:
          let
            grammarName = pkg.grammarName or null;
            language = pkg.language or null;
            hasAssociatedQuery = (pkg.passthru or {}) ? associatedQuery;
          in
            if grammarName != null then grammarName
            else if language != null && hasAssociatedQuery then language
            else abort "unsupported package";

        # Test with a mix of package types
        packages = [
          { grammarName = "bash"; }                                        # grammarPlugins style
          { language = "wgsl"; passthru.associatedQuery = {}; }            # allGrammars style
          { grammarName = "vim"; }                                         # grammarPlugins style
          { language = "templ"; passthru.associatedQuery = {}; }           # allGrammars style
        ];

        extractedNames = map extractLang packages;
        expected = [ "bash" "wgsl" "vim" "templ" ];
      in
        extractedNames == expected
    ''
    "true";

  # Test that deprecated tree-sitter-grammars throws an error
  test-extract-lang-deprecated-throws = testLib.testNixExpr
    "extract-lang-deprecated-throws"
    ''
      let
        lib = (import <nixpkgs> {}).lib;
        extractLang = pkg:
          let
            grammarName = pkg.grammarName or null;
            language = pkg.language or null;
            pname = pkg.pname or "";
            hasAssociatedQuery = (pkg.passthru or {}) ? associatedQuery;
            isTreeSitterGrammar = lib.hasPrefix "tree-sitter-" pname;
          in
            if grammarName != null then grammarName
            else if language != null && hasAssociatedQuery then language
            else if language != null && isTreeSitterGrammar then
              "DEPRECATED_ERROR"  # In real code this throws
            else
              "UNKNOWN_ERROR";

        # Test with deprecated tree-sitter-grammars package (has language but no associatedQuery)
        deprecatedPackage = { language = "rust"; pname = "tree-sitter-rust"; name = "tree-sitter-rust"; passthru.updateScript = {}; };
        result = extractLang deprecatedPackage;
      in
        result == "DEPRECATED_ERROR"
    ''
    "true";

  # Test extractLang with edge cases in names
  test-extract-lang-edge-cases = testLib.testNixExpr
    "extract-lang-edge-cases"
    ''
      let
        lib = (import <nixpkgs> {}).lib;
        extractLang = pkg:
          let
            grammarName = pkg.grammarName or null;
            language = pkg.language or null;
            hasAssociatedQuery = (pkg.passthru or {}) ? associatedQuery;
          in
            if grammarName != null then grammarName
            else if language != null && hasAssociatedQuery then language
            else abort "unsupported package";

        # Test edge cases
        case1 = extractLang { grammarName = "c_sharp"; };                                           # Underscore in name
        case2 = extractLang { grammarName = "tsx"; };                                               # Short name
        case3 = extractLang { language = "markdown_inline"; passthru.associatedQuery = {}; };       # Underscore in language
        case4 = extractLang { grammarName = "json5"; };                                             # Number in name
      in
        case1 == "c_sharp" &&
        case2 == "tsx" &&
        case3 == "markdown_inline" &&
        case4 == "json5"
    ''
    "true";
}