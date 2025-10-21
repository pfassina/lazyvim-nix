# Simple regression tests using compile-time checks
{ pkgs, testLib, moduleUnderTest }:

let
  # Load the files at evaluation time
  pluginsJsonExists = builtins.pathExists ../../data/plugins.json;
  moduleNixExists = builtins.pathExists ../../nix/module.nix;
  flakeNixExists = builtins.pathExists ../../flake.nix;
  pluginMappingsExists = builtins.pathExists ../../data/mappings.json;

  # Load and parse plugins.json
  pluginsData = if pluginsJsonExists then
    builtins.fromJSON (builtins.readFile ../../data/plugins.json)
  else
    { plugins = []; extraction_report = {}; };

  pluginCount = builtins.length pluginsData.plugins;
  hasExtractionReport = pluginsData ? extraction_report;
  hasLazyVimPlugin = builtins.any (p: p.name == "LazyVim/LazyVim") pluginsData.plugins;

in {
  # Test that core files exist (compile-time check)
  test-core-files-exist = testLib.testNixExpr
    "core-files-exist"
    ''
      let
        flakeExists = ${if flakeNixExists then "true" else "false"};
        moduleExists = ${if moduleNixExists then "true" else "false"};
        pluginsExists = ${if pluginsJsonExists then "true" else "false"};
        mappingsExists = ${if pluginMappingsExists then "true" else "false"};
      in flakeExists && moduleExists && pluginsExists && mappingsExists
    ''
    "true";

  # Test plugin count is reasonable
  test-plugin-count = testLib.testNixExpr
    "plugin-count"
    ''
      let
        count = ${toString pluginCount};
        reasonable = count >= 20;
      in reasonable
    ''
    "true";

  # Test LazyVim core plugin exists
  test-lazyvim-plugin-exists = testLib.testNixExpr
    "lazyvim-plugin-exists"
    ''${if hasLazyVimPlugin then "true" else "false"}''
    "true";

  # Test extraction report exists
  test-extraction-report = testLib.testNixExpr
    "extraction-report"
    ''${if hasExtractionReport then "true" else "false"}''
    "true";

  # Test plugin count consistency
  test-plugin-count-consistency = testLib.testNixExpr
    "plugin-count-consistency"
    ''
      let
        reportedCount = ${toString (pluginsData.extraction_report.total_plugins or 0)};
        actualCount = ${toString pluginCount};
      in reportedCount == actualCount
    ''
    "true";
}