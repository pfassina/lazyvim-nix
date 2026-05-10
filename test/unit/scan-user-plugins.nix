# Unit tests for the pure-Nix scanUserPlugins implementation
{ pkgs, testLib, moduleUnderTest }:

let
  fileScanning = import ../../nix/lib/file-scanning.nix {
    inherit (pkgs) lib;
    inherit pkgs;
    config = {};
  };

  # Fixture: a config tree containing lua/plugins/ with both a top-level
  # file and a nested subdirectory; one plugin name appears in both files
  # to exercise dedup.
  fixtureWithPlugins = pkgs.runCommand "scan-user-plugins-fixture" {} ''
    mkdir -p $out/lua/plugins/category
    cat > $out/lua/plugins/top.lua <<'EOF'
    return {
      { "LazyVim/LazyVim" },
      { "folke/lazy.nvim", dependencies = { "nvim-lua/plenary.nvim" } },
      { "folke/lazy.nvim" },
    }
    EOF
    cat > $out/lua/plugins/category/nested.lua <<'EOF'
    return { { "owner/nested-plugin" } }
    EOF
  '';

  # Fixture: a directory that exists but has no lua/plugins/ subdirectory.
  fixtureMissingPluginsDir = pkgs.runCommand "scan-user-plugins-no-plugins" {} ''
    mkdir -p $out/lua/config
    echo "-- no plugins here" > $out/lua/config/options.lua
  '';

in {
  test-scan-user-plugins-missing-path = testLib.testNixExpr
    "scan-user-plugins-missing-path"
    ''
      let
        fs = import ${../../nix/lib/file-scanning.nix} {
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
          config = {};
        };
      in builtins.length (fs.scanUserPlugins /no/such/path/here)
    ''
    "0";

  test-scan-user-plugins-missing-plugins-dir = testLib.testNixExpr
    "scan-user-plugins-missing-plugins-dir"
    ''
      let
        fs = import ${../../nix/lib/file-scanning.nix} {
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
          config = {};
        };
      in builtins.length (fs.scanUserPlugins ${fixtureMissingPluginsDir})
    ''
    "0";

  test-scan-user-plugins-extracts-top-level = testLib.testNixExpr
    "scan-user-plugins-extracts-top-level"
    ''
      let
        fs = import ${../../nix/lib/file-scanning.nix} {
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
          config = {};
        };
        names = map (s: s.name) (fs.scanUserPlugins ${fixtureWithPlugins});
      in builtins.elem "LazyVim/LazyVim" names
    ''
    "true";

  test-scan-user-plugins-recurses-subdirectories = testLib.testNixExpr
    "scan-user-plugins-recurses-subdirectories"
    ''
      let
        fs = import ${../../nix/lib/file-scanning.nix} {
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
          config = {};
        };
        names = map (s: s.name) (fs.scanUserPlugins ${fixtureWithPlugins});
      in builtins.elem "owner/nested-plugin" names
    ''
    "true";

  test-scan-user-plugins-dedups = testLib.testNixExpr
    "scan-user-plugins-dedups"
    ''
      let
        fs = import ${../../nix/lib/file-scanning.nix} {
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
          config = {};
        };
        names = map (s: s.name) (fs.scanUserPlugins ${fixtureWithPlugins});
        lazyCount = builtins.length (builtins.filter (n: n == "folke/lazy.nvim") names);
      in lazyCount
    ''
    "1";

  test-scan-user-plugins-sorted = testLib.testNixExpr
    "scan-user-plugins-sorted"
    ''
      let
        lib = (import <nixpkgs> {}).lib;
        fs = import ${../../nix/lib/file-scanning.nix} {
          inherit lib;
          pkgs = import <nixpkgs> {};
          config = {};
        };
        names = map (s: s.name) (fs.scanUserPlugins ${fixtureWithPlugins});
        sorted = lib.sort (a: b: a < b) names;
      in names == sorted
    ''
    "true";

  test-scan-user-plugins-spec-shape = testLib.testNixExpr
    "scan-user-plugins-spec-shape"
    ''
      let
        fs = import ${../../nix/lib/file-scanning.nix} {
          lib = (import <nixpkgs> {}).lib;
          pkgs = import <nixpkgs> {};
          config = {};
        };
        specs = fs.scanUserPlugins ${fixtureWithPlugins};
        first = builtins.head specs;
      in first ? name && first ? owner && first ? repo && first ? source_file && first ? user_plugin
    ''
    "true";
}
