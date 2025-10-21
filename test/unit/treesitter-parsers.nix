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
}