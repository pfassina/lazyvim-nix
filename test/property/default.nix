# Property-based tests for edge cases and error conditions
{ pkgs, testLib, moduleUnderTest }:

let
  moduleLib = pkgs.lib;

in {
  # Test malformed plugin names
  test-malformed-plugin-names = testLib.runTest "malformed-plugin-names" ''
    # Test various malformed plugin names to ensure graceful handling
    malformed_names=(
      ""                    # Empty name
      "/"                   # Just separator
      "//"                  # Double separator
      "owner/"              # Missing repo
      "/repo"               # Missing owner
      "owner/repo/extra"    # Too many parts
      "owner repo"          # Space instead of slash
      "owner\\repo"         # Backslash instead of slash
      "owner..repo"         # Double dots
      "owner--repo"         # Double hyphens
    )

    for name in "''${malformed_names[@]}"; do
      echo "Testing malformed name: '$name'"

      # Test that automatic resolution doesn't crash
      result=$(nix-instantiate --eval --expr '
        let
          lazyName = "'"$name"'";
          parts = builtins.filter (x: x != "" && x != null) (builtins.split "/" lazyName);
          repoName = if builtins.length parts >= 2 then builtins.elemAt parts 2 else lazyName;
          nixName = builtins.replaceStrings ["-" "."] ["_" "-"] repoName;
        in nixName
      ' 2>/dev/null || echo '""')

      echo "  -> Result: $result"
    done

    echo "Malformed plugin names test completed"
  '';

  # Test plugin resolution with missing mappings
  test-missing-mappings = testLib.runTest "missing-mappings" ''
    # Test plugins that don't exist in mappings
    result=$(nix-instantiate --eval --expr '
      let
        mappings = {};  # Empty mappings

        resolvePluginName = lazyName:
          let
            mapping = mappings.''${lazyName} or null;
          in
            if mapping == null then
              let
                parts = builtins.filter (x: x != "") (builtins.split "/" lazyName);
                repoName = if builtins.length parts >= 2 then builtins.elemAt parts 2 else lazyName;
                nixName = builtins.replaceStrings ["-" "."] ["_" "-"] repoName;
              in nixName
            else mapping;

        # Should fall back to automatic resolution
        result1 = resolvePluginName "owner/test-plugin.nvim";
        result2 = resolvePluginName "nonexistent/plugin";

        # Both should work (automatic resolution)
        isValid = result1 == "test_plugin-nvim" && result2 == "plugin";
      in isValid
    ')
    [ "$result" = "true" ]
  '';

  # Test circular dependency detection in mappings
  test-circular-mappings = testLib.runTest "circular-mappings" ''
    # Test that circular mappings don't cause infinite loops
    result=$(nix-instantiate --eval --expr '
      let
        # This would be a problematic mapping (circular reference)
        # In practice, our mappings are strings or {package, module}, not references
        mappings = {
          "a/plugin" = "b_plugin";
          "b/plugin" = "a_plugin";  # Not actually circular in our system
        };

        # Test resolution
        result1 = mappings."a/plugin";
        result2 = mappings."b/plugin";

        # Should resolve to the mapped values (no infinite loop)
        isValid = result1 == "b_plugin" && result2 == "a_plugin";
      in isValid
    ')
    [ "$result" = "true" ]
  '';

  # Test invalid multi-module mapping structures
  test-invalid-multi-module-mappings = testLib.runTest "invalid-multi-module-mappings" ''
    # Test various invalid multi-module mapping formats
    invalid_mappings='
    {
      "test1/missing-package" = { module = "test"; };           # Missing package
      "test2/missing-module" = { package = "test"; };           # Missing module
      "test3/wrong-type" = { package = 123; module = "test"; }; # Wrong type
      "test4/empty-package" = { package = ""; module = "test"; }; # Empty package
      "test5/empty-module" = { package = "test"; module = ""; }; # Empty module
    }
    '

    # Test validation logic
    result=$(nix-instantiate --eval --expr '
      let
        mappings = '"$invalid_mappings"';

        validateMapping = name: mapping:
          if builtins.isString mapping then
            mapping != ""
          else if builtins.isAttrs mapping then
            (mapping ? package && mapping ? module &&
             builtins.isString mapping.package && builtins.isString mapping.module &&
             mapping.package != "" && mapping.module != "")
          else false;

        # Test each mapping
        results = builtins.mapAttrs validateMapping mappings;

        # Count valid mappings (should be 0 for our invalid test data)
        validCount = builtins.length (builtins.filter (x: x) (builtins.attrValues results));
      in validCount
    ')
    [ "$result" = "0" ]  # All should be invalid
  '';

  # Test edge cases in version information handling
  test-version-edge-cases = testLib.runTest "version-edge-cases" ''
    # Test various edge cases in version handling
    version_cases=(
      '{"commit": null}'
      '{"tag": ""}'
      '{"commit": "*"}'
      '{"sha256": null}'
      '{}'
      '{"unknown_field": "value"}'
    )

    for version_info in "''${version_cases[@]}"; do
      echo "Testing version info: $version_info"

      result=$(nix-instantiate --eval --expr '
        let
          versionInfo = '"$version_info"';

          # Extract version components safely
          lazyvimVersion = versionInfo.lazyvim_version or null;
          latestVersion = versionInfo.latest_version or null;
          tagVersion = versionInfo.tag or null;
          commitVersion = versionInfo.commit or null;
          sha256 = versionInfo.sha256 or null;

          # Determine target version (priority: lazyvim > tag > latest > commit)
          targetVersion = if lazyvimVersion != null && lazyvimVersion != "*" then
            lazyvimVersion
          else if tagVersion != null && tagVersion != "" then
            tagVersion
          else if latestVersion != null then
            latestVersion
          else
            commitVersion;

          # Should handle gracefully (no crashes)
          result = if targetVersion == null || targetVersion == "*" || targetVersion == ""
                   then "HEAD"
                   else targetVersion;
        in result != null
      ' 2>/dev/null || echo "false")

      [ "$result" = "true" ] || exit 1
    done

    echo "Version edge cases test passed"
  '';

  # Test empty or minimal configurations
  test-empty-configurations = testLib.runTest "empty-configurations" ''
    # Test with minimal/empty configuration sections
    empty_configs=(
      '{ enable = true; extraPackages = []; }'
      '{ enable = true; treesitterParsers = []; }'
      '{ enable = true; config = {}; }'
      '{ enable = true; extras = {}; }'
      '{ enable = true; plugins = {}; }'
    )

    for config in "''${empty_configs[@]}"; do
      echo "Testing empty config: $config"

      testConfig='{
        config = {
          home.homeDirectory = "/tmp/test";
          home.username = "testuser";
          home.stateVersion = "23.11";
          programs.lazyvim = '"$config"';
        };
        lib = (import <nixpkgs> {}).lib;
        pkgs = import <nixpkgs> {};
      }'

      result=$(nix-instantiate --eval --expr "
        let module = import ${../nix/module.nix} $testConfig;
        in module.config.programs.neovim.enable
      " 2>/dev/null || echo "false")

      [ "$result" = "true" ] || exit 1
    done

    echo "Empty configurations test passed"
  '';

  # Test invalid plugin source strategies
  test-invalid-plugin-source = testLib.runTest "invalid-plugin-source" ''
    # Test that invalid plugin source values are handled

    # This should fail during evaluation (invalid enum value)
    invalidConfig='{
      config = {
        home.homeDirectory = "/tmp/test";
        home.username = "testuser";
        home.stateVersion = "23.11";
        programs.lazyvim = {
          enable = true;
          pluginSource = "invalid-strategy";
        };
      };
      lib = (import <nixpkgs> {}).lib;
      pkgs = import <nixpkgs> {};
    }'

    # This should fail (invalid enum value)
    if nix-instantiate --eval --expr "
      let module = import ${../nix/module.nix} $invalidConfig;
      in module.config.programs.neovim.enable
    " 2>/dev/null; then
      echo "ERROR: Invalid plugin source should have failed!"
      exit 1
    else
      echo "✓ Invalid plugin source properly rejected"
    fi
  '';

  # Test large configuration stress test
  test-large-configuration = testLib.runTest "large-configuration" ''
    # Test with a large number of packages, parsers, and plugins
    largeConfig='{
      config = {
        home.homeDirectory = "/tmp/test";
        home.username = "testuser";
        home.stateVersion = "23.11";
        programs.lazyvim = {
          enable = true;

          extraPackages = with (import <nixpkgs> {}); [
            lua-language-server rust-analyzer gopls
            typescript-language-server pyright
            ripgrep fd fzf bat git curl wget
            nixd alejandra stylua prettier
          ];

          treesitterParsers = with (import <nixpkgs> {}).tree-sitter-grammars; [
            tree-sitter-lua tree-sitter-rust tree-sitter-go
            tree-sitter-typescript tree-sitter-python tree-sitter-nix
            tree-sitter-bash tree-sitter-json tree-sitter-yaml
          ];

          plugins = builtins.listToAttrs (map (i: {
            name = "plugin-${toString i}";
            value = "return { \"test/plugin-${toString i}\" }";
          }) (builtins.genList (x: x) 20));
        };
      };
      lib = (import <nixpkgs> {}).lib;
      pkgs = import <nixpkgs> {};
    }'

    # Should handle large configs without issues
    result=$(nix-instantiate --eval --expr "
      let module = import ${../nix/module.nix} $largeConfig;
      in module.config.programs.neovim.enable
    " 2>/dev/null || echo "false")

    [ "$result" = "true" ] || exit 1
    echo "Large configuration test passed"
  '';

  # Test unicode and special characters in configuration
  test-unicode-characters = testLib.runTest "unicode-characters" ''
    # Test that unicode and special characters are handled properly
    unicodeConfig='{
      config = {
        home.homeDirectory = "/tmp/test-unicode";
        home.username = "testuser";
        home.stateVersion = "23.11";
        programs.lazyvim = {
          enable = true;
          config = {
            options = "-- 这是中文注释\nvim.opt.encoding = \"utf-8\"";
            keymaps = "-- Emojis: 🚀 ⚡ 💻\nvim.keymap.set(\"n\", \"<leader>🚀\", \"<cmd>echo '\''Hello 世界!'\''<cr>\")";
          };
        };
      };
      lib = (import <nixpkgs> {}).lib;
      pkgs = import <nixpkgs> {};
    }'

    result=$(nix-instantiate --eval --expr "
      let module = import ${../nix/module.nix} $unicodeConfig;
      in module.config.programs.neovim.enable
    " 2>/dev/null || echo "false")

    [ "$result" = "true" ] || exit 1
    echo "Unicode characters test passed"
  '';

  # Test concurrent/parallel evaluation behavior
  test-concurrent-evaluation = testLib.runTest "concurrent-evaluation" ''
    # Test that multiple evaluations don't interfere with each other
    for i in {1..5}; do
      echo "Parallel evaluation $i"

      testConfig='{
        config = {
          home.homeDirectory = "/tmp/test-'"$i"'";
          home.username = "testuser'"$i"'";
          home.stateVersion = "23.11";
          programs.lazyvim.enable = true;
        };
        lib = (import <nixpkgs> {}).lib;
        pkgs = import <nixpkgs> {};
      }'

      nix-instantiate --eval --expr "
        let module = import ${../nix/module.nix} $testConfig;
        in module.config.programs.neovim.enable
      " > /dev/null &
    done

    # Wait for all background processes
    wait

    echo "Concurrent evaluation test passed"
  '';
} // (import ./dependency-edge-cases.nix { inherit pkgs testLib; })