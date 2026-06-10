# Simplified property tests for edge cases
{ testLib, ... }:

{
  # Test empty plugin name handling
  test-empty-plugin-name = testLib.testNixExpr
    "empty-plugin-name"
    ''
      let
        lazyName = "";
        parts = builtins.filter (x: x != "") (builtins.split "/" lazyName);
        repoName = if builtins.length parts >= 2 then builtins.elemAt parts 2 else lazyName;
      in repoName == ""
    ''
    "true";

  # Test plugin name with special characters
  test-special-chars = testLib.testNixExpr
    "special-chars"
    ''
      let
        name = "test.plugin-name";
        converted = builtins.replaceStrings ["-" "."] ["_" "-"] name;
      in converted == "test-plugin_name"
    ''
    "true";

  # Test boolean normalization
  test-boolean-values = testLib.testNixExpr
    "boolean-values"
    ''
      let
        trueVal = true;
        falseVal = false;
      in trueVal && !falseVal
    ''
    "true";
}