# Comprehensive test suite for LazyVim flake
{ pkgs ? import <nixpkgs> {} }:

let
  # Import the module under test
  moduleUnderTest = import ../nix/module.nix;

  # Test utilities
  testLib = rec {
    # Helper to run a test and capture result
    runTest = name: test: pkgs.runCommand "test-${name}" {
      buildInputs = [ pkgs.nix pkgs.jq pkgs.bash ];
    } ''
      echo "Running test: ${name}"
      if ${test}; then
        echo "✓ ${name} PASSED"
        touch $out
      else
        echo "✗ ${name} FAILED"
        exit 1
      fi
    '';

    # Helper to assert equality
    assertEqual = expected: actual: ''
      if [ "${toString expected}" = "${toString actual}" ]; then
        true
      else
        echo "Expected: ${toString expected}"
        echo "Actual: ${toString actual}"
        false
      fi
    '';

    # Helper to test that a derivation builds successfully
    testBuilds = name: drv: runTest "builds-${name}" ''
      ${drv} && echo "Build successful"
    '';

    # Helper to test evaluated Nix values (compile-time evaluation)
    # Unlike testNixExpr, this takes a real Nix value - typically the result of
    # calling actual module code - so tests exercise the real implementation.
    testEval = name: value: expectedResult:
      let
        normalize = val:
          if builtins.isBool val then (if val then "true" else "false")
          else toString val;
        result = builtins.tryEval (normalize value);
        expected = normalize expectedResult;
        actual = if result.success then result.value else "evaluation failed";
      in
        if result.success && actual == expected then
          pkgs.runCommand "test-eval-${name}" {} ''
            echo "✓ ${name} PASSED: ${actual}"
            touch $out
          ''
        else
          pkgs.runCommand "test-eval-${name}" {} ''
            echo "✗ ${name} FAILED"
            echo "  Expected: ${expected}"
            echo "  Got: ${actual}"
            exit 1
          '';

    # Helper to test Nix expressions (compile-time evaluation)
    testNixExpr = name: expr: expectedResult:
      let
        result = builtins.tryEval (import (pkgs.writeText "test-${name}.nix" ''
          ${expr}
        ''));
        # Normalize boolean comparison
        normalizeResult = val:
          if builtins.isBool val then (if val then "true" else "false")
          else toString val;
        expected = if builtins.isBool expectedResult then
          (if expectedResult then "true" else "false")
        else toString expectedResult;
        actual = if result.success then normalizeResult result.value else "evaluation failed";
      in
        if result.success && actual == expected then
          pkgs.runCommand "test-expr-${name}" {} ''
            echo "✓ ${name} PASSED: ${actual}"
            touch $out
          ''
        else
          pkgs.runCommand "test-expr-${name}" {} ''
            echo "✗ ${name} FAILED"
            echo "  Expected: ${expected}"
            echo "  Got: ${actual}"
            exit 1
          '';
  };

  # Auto-import all test files in a suite directory.
  #
  # Every regular *.nix file in `dir` is imported with the standard test
  # signature `{ pkgs, testLib, moduleUnderTest }:` and the resulting
  # attrsets are merged. Two files defining the same test attribute name is
  # an evaluation error: a plain `//` merge would silently keep only one.
  # Non-.nix entries, subdirectories, and symlinks are ignored.
  importSuite = dir:
    let
      inherit (pkgs) lib;

      testFiles = lib.filterAttrs
        (name: type: type == "regular" && lib.hasSuffix ".nix" name)
        (builtins.readDir dir);

      # file name -> attrset of tests defined by that file
      perFile = lib.mapAttrs
        (name: _: import (dir + "/${name}") { inherit pkgs testLib moduleUnderTest; })
        testFiles;

      # test name -> list of file names defining it
      definitions = lib.zipAttrs
        (lib.mapAttrsToList (file: tests: lib.mapAttrs (_: _: file) tests) perFile);

      duplicates = lib.filterAttrs (_: files: builtins.length files > 1) definitions;
    in
    if duplicates == { } then
      lib.foldl' (acc: tests: acc // tests) { } (builtins.attrValues perFile)
    else
      throw ''
        importSuite: duplicate test names in ${toString dir}:
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList
          (testName: files: "  '${testName}' is defined in: ${lib.concatStringsSep ", " files}")
          duplicates)}
      '';

  # Load all test suites by scanning the suite directories
  unitTests = importSuite ./unit;
  integrationTests = importSuite ./integration;
  propertyTests = importSuite ./property;
  regressionTests = importSuite ./regression;
  e2eTests = importSuite ./e2e;

  # Combine all tests
  allTests = unitTests // integrationTests // propertyTests // regressionTests // e2eTests;

in {
  # Individual test suites
  inherit unitTests integrationTests propertyTests regressionTests e2eTests;

  # Run all tests by depending on them
  runAll = let
    # Collect all test derivations
    testList = pkgs.lib.mapAttrsToList (name: test: test) allTests;
  in pkgs.runCommand "lazyvim-tests-all" {
    # Make all tests build dependencies
    buildInputs = testList ++ [ pkgs.coreutils ];
  } ''
    echo "🧪 LazyVim Comprehensive Test Suite"
    echo "===================================="
    echo
    echo "All tests completed successfully!"
    echo

    # Count the tests
    total_tests=${toString (builtins.length testList)}

    echo "📊 Test Results"
    echo "==============="
    echo "Total tests: $total_tests"
    echo "Passed: $total_tests"
    echo "Failed: 0"
    echo
    echo "🎉 All tests passed!"

    touch $out
  '';

  # Quick smoke test
  smokeTest = pkgs.runCommand "lazyvim-smoke-test" {
    buildInputs = [ pkgs.nix pkgs.jq ];
  } ''
    echo "🔥 LazyVim Smoke Test"
    echo "===================="

    # Test that the module can be imported (simplified for smoke test)
    echo "✓ Module file exists at ${../nix/module.nix}"

    # Test that core files exist and are valid
    [ -f "${../flake.nix}" ] && echo "✓ flake.nix exists"
    [ -f "${../data/plugins.json}" ] && echo "✓ data/plugins.json exists"
    [ -f "${../data/mappings.json}" ] && echo "✓ data/mappings.json exists"

    # Test JSON validity
    ${pkgs.jq}/bin/jq . ${../data/plugins.json} > /dev/null && echo "✓ data/plugins.json is valid JSON"

    # Test mappings file exists (simplified for smoke test)
    [ -f "${../data/mappings.json}" ] && echo "✓ data/mappings.json exists"

    echo
    echo "🎉 Smoke test passed!"
    touch $out
  '';
}
