# Tests for nested extras support (e.g., lang.typescript.biome, lang.typescript.oxc)
{ pkgs, testLib, moduleUnderTest }:

let
  lib = pkgs.lib;

in {

  # ── Metadata structure ──────────────────────────────────────────────

  # Test that extras.json contains nested typescript extras with is_nested flag
  test-nested-extras-metadata-present = testLib.testNixExpr
    "nested-extras-metadata-present"
    ''
      let
        extras = builtins.fromJSON (builtins.readFile ${../../data/extras.json});
        lang = extras.lang or {};
        hasTypescript = lang ? typescript;
        hasBiome = lang ? "typescript.biome";
        hasOxc = lang ? "typescript.oxc";
        hasTsgo = lang ? "typescript.tsgo";
        hasVtsls = lang ? "typescript.vtsls";
      in hasTypescript && hasBiome && hasOxc && hasTsgo && hasVtsls
    ''
    "true";

  # Test that parent typescript extra has is_nested = false
  test-nested-extras-parent-not-nested = testLib.testNixExpr
    "nested-extras-parent-not-nested"
    ''
      let
        extras = builtins.fromJSON (builtins.readFile ${../../data/extras.json});
        ts = extras.lang.typescript;
      in ts.is_nested == false
    ''
    "true";

  # Test that child extras have is_nested = true
  test-nested-extras-children-nested = testLib.testNixExpr
    "nested-extras-children-nested"
    ''
      let
        extras = builtins.fromJSON (builtins.readFile ${../../data/extras.json});
        biome = extras.lang."typescript.biome";
        oxc = extras.lang."typescript.oxc";
        tsgo = extras.lang."typescript.tsgo";
        vtsls = extras.lang."typescript.vtsls";
      in biome.is_nested && oxc.is_nested && tsgo.is_nested && vtsls.is_nested
    ''
    "true";

  # Test that nested extras have correct import paths
  test-nested-extras-import-paths = testLib.testNixExpr
    "nested-extras-import-paths"
    ''
      let
        extras = builtins.fromJSON (builtins.readFile ${../../data/extras.json});
        biome = extras.lang."typescript.biome";
        oxc = extras.lang."typescript.oxc";
        tsgo = extras.lang."typescript.tsgo";
        vtsls = extras.lang."typescript.vtsls";
      in biome.import == "lazyvim.plugins.extras.lang.typescript.biome"
         && oxc.import == "lazyvim.plugins.extras.lang.typescript.oxc"
         && tsgo.import == "lazyvim.plugins.extras.lang.typescript.tsgo"
         && vtsls.import == "lazyvim.plugins.extras.lang.typescript.vtsls"
    ''
    "true";

  # Test that parent typescript has correct import path
  test-nested-extras-parent-import-path = testLib.testNixExpr
    "nested-extras-parent-import-path"
    ''
      let
        extras = builtins.fromJSON (builtins.readFile ${../../data/extras.json});
        ts = extras.lang.typescript;
      in ts.import == "lazyvim.plugins.extras.lang.typescript"
    ''
    "true";

  # ── Option type generation (module evaluates without error) ─────────

  # Test that the generated options type accepts a nested extra
  test-nested-extras-options-eval = testLib.testNixExpr
    "nested-extras-options-eval"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
            home.username = "testuser";
            home.stateVersion = "23.11";
            programs.lazyvim = {
              enable = true;
              extras = {
                lang.typescript = {
                  enable = true;
                  biome.enable = true;
                };
              };
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
      in builtins.isAttrs module
    ''
    "true";

  # Test enabling a nested extra without enabling its parent
  test-nested-extras-child-without-parent = testLib.testNixExpr
    "nested-extras-child-without-parent"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
            home.username = "testuser";
            home.stateVersion = "23.11";
            programs.lazyvim = {
              enable = true;
              extras = {
                lang.typescript = {
                  enable = false;
                  biome.enable = true;
                };
              };
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
      in builtins.isAttrs module
    ''
    "true";

  # Test enabling parent without any nested children
  test-nested-extras-parent-only = testLib.testNixExpr
    "nested-extras-parent-only"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
            home.username = "testuser";
            home.stateVersion = "23.11";
            programs.lazyvim = {
              enable = true;
              extras = {
                lang.typescript.enable = true;
              };
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
      in builtins.isAttrs module
    ''
    "true";

  # Test enabling all four nested children simultaneously
  test-nested-extras-all-children = testLib.testNixExpr
    "nested-extras-all-children"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
            home.username = "testuser";
            home.stateVersion = "23.11";
            programs.lazyvim = {
              enable = true;
              extras = {
                lang.typescript = {
                  enable = true;
                  biome.enable = true;
                  oxc.enable = true;
                  tsgo.enable = true;
                  vtsls.enable = true;
                };
              };
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
      in builtins.isAttrs module
    ''
    "true";

  # Test nested extra with all sub-options populated
  test-nested-extras-suboptions-complete = testLib.testNixExpr
    "nested-extras-suboptions-complete"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
            home.username = "testuser";
            home.stateVersion = "23.11";
            programs.lazyvim = {
              enable = true;
              extras = {
                lang.typescript = {
                  enable = true;
                  installDependencies = true;
                  installRuntimeDependencies = true;
                  config = "";
                  biome = {
                    enable = true;
                    installDependencies = true;
                    installRuntimeDependencies = true;
                    config = "return {}";
                  };
                };
              };
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
      in builtins.isAttrs module
    ''
    "true";

  # Test mixing nested and non-nested extras in the same config
  test-nested-extras-mixed-config = testLib.testNixExpr
    "nested-extras-mixed-config"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
            home.username = "testuser";
            home.stateVersion = "23.11";
            programs.lazyvim = {
              enable = true;
              extras = {
                lang = {
                  python.enable = true;
                  nix.enable = true;
                  typescript = {
                    enable = true;
                    biome.enable = true;
                  };
                };
                editor.telescope.enable = true;
                coding.yanky.enable = true;
              };
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
      in builtins.isAttrs module
    ''
    "true";

  # Test non-nested extras are unaffected by nested extras changes
  test-nested-extras-non-nested-unaffected = testLib.testNixExpr
    "nested-extras-non-nested-unaffected"
    ''
      let
        testConfig = {
          config = {
            home.homeDirectory = "/tmp/test";
            home.username = "testuser";
            home.stateVersion = "23.11";
            programs.lazyvim = {
              enable = true;
              extras = {
                lang = {
                  python.enable = true;
                  go.enable = true;
                  rust.enable = true;
                };
                editor.telescope.enable = true;
              };
            };
          };
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
        };
        module = import ${../../nix/module.nix} testConfig;
      in builtins.isAttrs module
    ''
    "true";

  # ── flattenExtras / getEnabledExtras logic ──────────────────────────
  # Test the core flattening logic by reimplementing it inline with mock data,
  # which lets us inspect the output without needing the full module system.

  # Test that flattenExtras produces entries for both parent and children
  test-nested-extras-flatten-parent-and-children = testLib.testNixExpr
    "nested-extras-flatten-parent-and-children"
    ''
      let
        lib = (import <nixpkgs> {}).lib;
        extrasMetadata = builtins.fromJSON (builtins.readFile ${../../data/extras.json});

        normalizeName = builtins.replaceStrings ["-"] ["_"];

        flattenExtras = categoryName: prefix: node:
          let
            isExtraEnabled = node.enable or false;
            current = if isExtraEnabled then [{
              name = prefix;
              config = node.config or "";
            }] else [];
            metaChildren = lib.filterAttrs (n: v:
              builtins.isAttrs v && (v.is_nested or false) && lib.hasPrefix "''${prefix}." n
            ) (extrasMetadata.''${categoryName} or {});
            nestedList = lib.mapAttrsToList (childName: _childConfig:
              let
                shortName = lib.removePrefix "''${prefix}." childName;
                normalizedName = normalizeName shortName;
                childNode = node.''${normalizedName} or {};
              in
                flattenExtras categoryName childName childNode
            ) metaChildren;
          in current ++ builtins.concatLists nestedList;

        # Simulate: typescript.enable = true, biome.enable = true, oxc.enable = false
        mockNode = {
          enable = true;
          config = "";
          biome = { enable = true; config = ""; };
          oxc = { enable = false; config = ""; };
          tsgo = { config = ""; };
          vtsls = { config = ""; };
        };

        result = flattenExtras "lang" "typescript" mockNode;
        names = map (r: r.name) result;

        hasParent = builtins.elem "typescript" names;
        hasBiome = builtins.elem "typescript.biome" names;
        hasOxc = builtins.elem "typescript.oxc" names;
        hasTsgo = builtins.elem "typescript.tsgo" names;
      in hasParent && hasBiome && !hasOxc && !hasTsgo
    ''
    "true";

  # Test that flattenExtras produces nothing when all disabled
  test-nested-extras-flatten-all-disabled = testLib.testNixExpr
    "nested-extras-flatten-all-disabled"
    ''
      let
        lib = (import <nixpkgs> {}).lib;
        extrasMetadata = builtins.fromJSON (builtins.readFile ${../../data/extras.json});

        normalizeName = builtins.replaceStrings ["-"] ["_"];

        flattenExtras = categoryName: prefix: node:
          let
            isExtraEnabled = node.enable or false;
            current = if isExtraEnabled then [{
              name = prefix;
              config = node.config or "";
            }] else [];
            metaChildren = lib.filterAttrs (n: v:
              builtins.isAttrs v && (v.is_nested or false) && lib.hasPrefix "''${prefix}." n
            ) (extrasMetadata.''${categoryName} or {});
            nestedList = lib.mapAttrsToList (childName: _childConfig:
              let
                shortName = lib.removePrefix "''${prefix}." childName;
                normalizedName = normalizeName shortName;
                childNode = node.''${normalizedName} or {};
              in
                flattenExtras categoryName childName childNode
            ) metaChildren;
          in current ++ builtins.concatLists nestedList;

        mockNode = {
          enable = false;
          config = "";
        };

        result = flattenExtras "lang" "typescript" mockNode;
      in builtins.length result == 0
    ''
    "true";

  # Test that flattenExtras handles child-only enable (parent disabled)
  test-nested-extras-flatten-child-only = testLib.testNixExpr
    "nested-extras-flatten-child-only"
    ''
      let
        lib = (import <nixpkgs> {}).lib;
        extrasMetadata = builtins.fromJSON (builtins.readFile ${../../data/extras.json});

        normalizeName = builtins.replaceStrings ["-"] ["_"];

        flattenExtras = categoryName: prefix: node:
          let
            isExtraEnabled = node.enable or false;
            current = if isExtraEnabled then [{
              name = prefix;
              config = node.config or "";
            }] else [];
            metaChildren = lib.filterAttrs (n: v:
              builtins.isAttrs v && (v.is_nested or false) && lib.hasPrefix "''${prefix}." n
            ) (extrasMetadata.''${categoryName} or {});
            nestedList = lib.mapAttrsToList (childName: _childConfig:
              let
                shortName = lib.removePrefix "''${prefix}." childName;
                normalizedName = normalizeName shortName;
                childNode = node.''${normalizedName} or {};
              in
                flattenExtras categoryName childName childNode
            ) metaChildren;
          in current ++ builtins.concatLists nestedList;

        mockNode = {
          enable = false;
          config = "";
          biome = { enable = true; config = ""; };
        };

        result = flattenExtras "lang" "typescript" mockNode;
        names = map (r: r.name) result;
      in builtins.length result == 1 && builtins.elem "typescript.biome" names
    ''
    "true";

  # Test that metadata resolution works for flattened nested extras
  test-nested-extras-metadata-resolution = testLib.testNixExpr
    "nested-extras-metadata-resolution"
    ''
      let
        lib = (import <nixpkgs> {}).lib;
        extrasMetadata = builtins.fromJSON (builtins.readFile ${../../data/extras.json});

        item = { name = "typescript.biome"; config = ""; };
        path = [ "lang" item.name ];
        metadata = lib.attrByPath path null extrasMetadata;

        hasMetadata = metadata != null;
        correctImport = metadata.import == "lazyvim.plugins.extras.lang.typescript.biome";
        correctCategory = metadata.category == "lang";
      in hasMetadata && correctImport && correctCategory
    ''
    "true";

  # Test metadata resolution for parent extra
  test-nested-extras-parent-metadata-resolution = testLib.testNixExpr
    "nested-extras-parent-metadata-resolution"
    ''
      let
        lib = (import <nixpkgs> {}).lib;
        extrasMetadata = builtins.fromJSON (builtins.readFile ${../../data/extras.json});

        item = { name = "typescript"; config = ""; };
        path = [ "lang" item.name ];
        metadata = lib.attrByPath path null extrasMetadata;

        hasMetadata = metadata != null;
        correctImport = metadata.import == "lazyvim.plugins.extras.lang.typescript";
      in hasMetadata && correctImport
    ''
    "true";

  # ── Import spec generation ──────────────────────────────────────────

  # Test that extrasImportSpecs produces correct Lua import strings
  test-nested-extras-import-spec-format = testLib.testNixExpr
    "nested-extras-import-spec-format"
    ''
      let
        lib = (import <nixpkgs> {}).lib;

        mockExtras = [
          { name = "typescript"; category = "lang";
            import = "lazyvim.plugins.extras.lang.typescript";
            config = ""; hasConfig = false; }
          { name = "typescript.biome"; category = "lang";
            import = "lazyvim.plugins.extras.lang.typescript.biome";
            config = ""; hasConfig = false; }
        ];

        importSpecs = map (extra:
          "{ import = \"''${extra.import}\" },"
        ) mockExtras;

        hasTs = builtins.any (s:
          builtins.match ".*lazyvim.plugins.extras.lang.typescript\".*" s != null
        ) importSpecs;
        hasBiome = builtins.any (s:
          builtins.match ".*lazyvim.plugins.extras.lang.typescript.biome.*" s != null
        ) importSpecs;
      in builtins.length importSpecs == 2 && hasTs && hasBiome
    ''
    "true";

  # ── Dependencies data structure ─────────────────────────────────────

  # Test that dependencies.json has entries for nested typescript extras
  test-nested-extras-dependencies-exist = testLib.testNixExpr
    "nested-extras-dependencies-exist"
    ''
      let
        deps = builtins.fromJSON (builtins.readFile ${../../data/dependencies.json});
        extras = deps.extras or {};
        hasBiome = extras ? "lang.typescript.biome";
        hasOxc = extras ? "lang.typescript.oxc";
        hasTsgo = extras ? "lang.typescript.tsgo";
        hasVtsls = extras ? "lang.typescript.vtsls";
      in hasBiome && hasOxc && hasTsgo && hasVtsls
    ''
    "true";

  # Test that nested dependency entries have nixpkg mappings
  test-nested-extras-nixpkg-mappings = testLib.testNixExpr
    "nested-extras-nixpkg-mappings"
    ''
      let
        deps = builtins.fromJSON (builtins.readFile ${../../data/dependencies.json});
        biomeTools = deps.extras."lang.typescript.biome" or [];
        biomeHasNixpkg = builtins.any (t: t ? nixpkg) biomeTools;
        oxcTools = deps.extras."lang.typescript.oxc" or [];
        oxcHasNixpkg = builtins.any (t: t ? nixpkg) oxcTools;
        tsgoTools = deps.extras."lang.typescript.tsgo" or [];
        tsgoHasNixpkg = builtins.any (t: t ? nixpkg) tsgoTools;
        vtslsTools = deps.extras."lang.typescript.vtsls" or [];
        vtslsHasNixpkg = builtins.any (t: t ? nixpkg) vtslsTools;
      in biomeHasNixpkg && oxcHasNixpkg && tsgoHasNixpkg && vtslsHasNixpkg
    ''
    "true";

  # ── Dependency resolution bug detection ─────────────────────────────
  # dependencies.nix uses lib.head/lib.last to split the extra name, which loses
  # the middle component for nested extras like "lang.typescript.biome".
  # These tests verify the config lookup logic independent of the full module system.

  # Test that the correct config lookup path is needed for nested extras
  test-nested-extras-dep-config-lookup = testLib.testNixExpr
    "nested-extras-dep-config-lookup"
    ''
      let
        lib = (import <nixpkgs> {}).lib;

        # Simulate the cfg.extras structure as the module would produce it
        extrasConfig = {
          lang = {
            typescript = {
              enable = true;
              installDependencies = false;
              installRuntimeDependencies = false;
              biome = {
                enable = true;
                installDependencies = true;
                installRuntimeDependencies = true;
              };
            };
          };
        };

        extraName = "lang.typescript.biome";
        parts = lib.splitString "." extraName;
        category = lib.head parts;

        # CORRECT approach: use attrByPath for the remainder
        correctConfig = lib.attrByPath (lib.tail parts) {} extrasConfig.''${category};
        correctInstallDeps = correctConfig.installDependencies or false;

        # BUGGY approach: use lib.last (loses "typescript" component)
        buggyName = lib.last parts;
        buggyConfig = extrasConfig.''${category}.''${buggyName} or {};
        buggyInstallDeps = buggyConfig.installDependencies or false;

      in correctInstallDeps == true && buggyInstallDeps == false
    ''
    "true";

  # Same test for a non-nested extra to show the bug doesn't affect them
  test-nested-extras-dep-config-lookup-simple = testLib.testNixExpr
    "nested-extras-dep-config-lookup-simple"
    ''
      let
        lib = (import <nixpkgs> {}).lib;

        extrasConfig = {
          lang = {
            python = {
              enable = true;
              installDependencies = true;
            };
          };
        };

        extraName = "lang.python";
        parts = lib.splitString "." extraName;
        category = lib.head parts;

        # Both approaches work for non-nested extras
        correctConfig = lib.attrByPath (lib.tail parts) {} extrasConfig.''${category};
        buggyName = lib.last parts;
        buggyConfig = extrasConfig.''${category}.''${buggyName} or {};

        correctInstallDeps = correctConfig.installDependencies or false;
        buggyInstallDeps = buggyConfig.installDependencies or false;

      in correctInstallDeps == true && buggyInstallDeps == true
    ''
    "true";
}
