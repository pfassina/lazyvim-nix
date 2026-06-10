# Unit tests for the pure-Nix scanUserPlugins implementation
{ pkgs, testLib, moduleUnderTest }:

let
  lib = pkgs.lib;

  # The real file scanning library under test
  fileScanning = import ../../nix/lib/file-scanning.nix {
    inherit lib pkgs;
    config = { };
  };

  inherit (fileScanning) scanUserPlugins scanConfigFiles detectConflicts;

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

  # Fixture: a configFiles directory mixing both supported layouts (flat
  # config/ + plugins/ and lua/-prefixed), plus files that must be ignored
  # (non-Lua files and Lua files outside the recognized categories). This is
  # a checked-in directory rather than a derivation because scanConfigFiles
  # derives attribute names from file paths, which must be context-free -
  # exactly like the user-supplied path the real module receives.
  scannedConfigFiles = scanConfigFiles ../fixtures/config-files "nvim";

  # cfg shape consumed by detectConflicts
  noInlineConfig = {
    config = { options = ""; keymaps = ""; autocmds = ""; };
    plugins = { };
  };

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

  # scanConfigFiles: a null path yields empty results
  test-scan-config-files-null-path = testLib.testEval
    "scan-config-files-null-path"
    (let result = scanConfigFiles null "nvim";
     in result.configFiles == { } && result.pluginFiles == { })
    true;

  # scanConfigFiles: a nonexistent path fails loudly
  test-scan-config-files-missing-path-throws = testLib.testEval
    "scan-config-files-missing-path-throws"
    (builtins.tryEval (scanConfigFiles /no/such/path/here "nvim")).success
    false;

  # scanConfigFiles: flat config/ layout is mapped under lua/
  test-scan-config-files-flat-layout = testLib.testEval
    "scan-config-files-flat-layout"
    scannedConfigFiles.configFiles.options.targetPath
    "nvim/lua/config/options.lua";

  # scanConfigFiles: lua/-prefixed layout is used as-is
  test-scan-config-files-lua-prefixed-layout = testLib.testEval
    "scan-config-files-lua-prefixed-layout"
    scannedConfigFiles.configFiles.keymaps.targetPath
    "nvim/lua/config/keymaps.lua";

  # scanConfigFiles: plugin files are categorized by plugin name
  test-scan-config-files-plugin-categorized = testLib.testEval
    "scan-config-files-plugin-categorized"
    scannedConfigFiles.pluginFiles.colorscheme.targetPath
    "nvim/lua/plugins/colorscheme.lua";

  # scanConfigFiles: non-Lua files and uncategorized Lua files are ignored
  test-scan-config-files-ignores-unrecognized = testLib.testEval
    "scan-config-files-ignores-unrecognized"
    (builtins.attrNames scannedConfigFiles.configFiles == [ "keymaps" "options" ] &&
     builtins.attrNames scannedConfigFiles.pluginFiles == [ "colorscheme" ])
    true;

  # detectConflicts: no conflict when inline config is empty
  test-detect-conflicts-none = testLib.testEval
    "detect-conflicts-none"
    (detectConflicts noInlineConfig scannedConfigFiles == null)
    true;

  # detectConflicts: configFiles and inline config for the same section throw
  test-detect-conflicts-inline-config-throws = testLib.testEval
    "detect-conflicts-inline-config-throws"
    (builtins.tryEval (detectConflicts (noInlineConfig // {
      config = { options = "vim.opt.number = true"; keymaps = ""; autocmds = ""; };
    }) scannedConfigFiles)).success
    false;

  # detectConflicts: configFiles and the plugins option for the same plugin throw
  test-detect-conflicts-plugin-throws = testLib.testEval
    "detect-conflicts-plugin-throws"
    (builtins.tryEval (detectConflicts (noInlineConfig // {
      plugins = { colorscheme = { }; };
    }) scannedConfigFiles)).success
    false;
}
