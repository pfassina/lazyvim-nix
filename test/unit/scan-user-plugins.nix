# Unit tests for the pure-Nix scanUserPlugins implementation
{ pkgs, testLib, moduleUnderTest }:

let
  lib = pkgs.lib;

  # The real file scanning library under test
  fileScanning = import ../../nix/lib/file-scanning.nix {
    inherit lib pkgs;
    config = { };
  };

  inherit (fileScanning) scanUserPlugins;

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

  scannedSpecs = scanUserPlugins fixtureWithPlugins;
  scannedNames = map (s: s.name) scannedSpecs;

in {
  test-scan-user-plugins-missing-path = testLib.testEval
    "scan-user-plugins-missing-path"
    (builtins.length (scanUserPlugins /no/such/path/here))
    0;

  test-scan-user-plugins-missing-plugins-dir = testLib.testEval
    "scan-user-plugins-missing-plugins-dir"
    (builtins.length (scanUserPlugins fixtureMissingPluginsDir))
    0;

  test-scan-user-plugins-extracts-top-level = testLib.testEval
    "scan-user-plugins-extracts-top-level"
    (builtins.elem "LazyVim/LazyVim" scannedNames)
    true;

  test-scan-user-plugins-recurses-subdirectories = testLib.testEval
    "scan-user-plugins-recurses-subdirectories"
    (builtins.elem "owner/nested-plugin" scannedNames)
    true;

  test-scan-user-plugins-dedups = testLib.testEval
    "scan-user-plugins-dedups"
    (builtins.length (builtins.filter (n: n == "folke/lazy.nvim") scannedNames))
    1;

  test-scan-user-plugins-sorted = testLib.testEval
    "scan-user-plugins-sorted"
    (scannedNames == lib.sort (a: b: a < b) scannedNames)
    true;

  test-scan-user-plugins-spec-shape = testLib.testEval
    "scan-user-plugins-spec-shape"
    (let first = builtins.head scannedSpecs;
     in first ? name && first ? owner && first ? repo && first ? source_file && first ? user_plugin)
    true;
}
