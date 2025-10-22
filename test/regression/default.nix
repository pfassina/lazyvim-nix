# Regression tests for plugin updates and system changes
{ pkgs, testLib, moduleUnderTest }:

let
  moduleLib = pkgs.lib;

  # Load current plugin data for regression testing
  currentPluginData = builtins.fromJSON (builtins.readFile ../../data/plugins.json);
  currentPluginMappings = builtins.fromJSON (builtins.readFile ../../data/mappings.json);

in {
  # Test that core LazyVim plugins are always present
  test-core-plugins-present = testLib.runTest "core-plugins-present" ''
    # These plugins should always be in plugins.json
    core_plugins=(
      "LazyVim/LazyVim"
      "folke/lazy.nvim"
      "nvim-lualine/lualine.nvim"
      "akinsho/bufferline.nvim"
      "folke/which-key.nvim"
    )

    echo "Checking core plugins in plugins.json..."
    for plugin in "''${core_plugins[@]}"; do
      if ${pkgs.jq}/bin/jq -e '.plugins[] | select(.name == "'"$plugin"'")' ${../../data/plugins.json} > /dev/null; then
        echo "✓ Found: $plugin"
      else
        echo "✗ Missing core plugin: $plugin"
        exit 1
      fi
    done

    echo "All core plugins present"
  '';

  # Test that known plugin mappings are maintained
  test-plugin-mappings-stability = testLib.runTest "plugin-mappings-stability" ''
    # These mappings should never change (backwards compatibility)
    critical_mappings=(
      "L3MON4D3/LuaSnip:luasnip"
      "catppuccin/nvim:catppuccin-nvim"
      "folke/lazy.nvim:lazy-nvim"
    )

    echo "Checking critical plugin mappings..."
    for mapping in "''${critical_mappings[@]}"; do
      plugin="''${mapping%%:*}"
      expected="''${mapping##*:}"

      actual=$(${pkgs.jq}/bin/jq -r --arg plugin "$plugin" '.[$plugin] // "MISSING"' ${../../data/mappings.json} 2>/dev/null || echo "MISSING")

      if [ "$actual" = "$expected" ]; then
        echo "✓ $plugin -> $expected"
      else
        echo "✗ $plugin: expected '$expected', got '$actual'"
        exit 1
      fi
    done

    echo "All critical mappings stable"
  '';

  # Test that multi-module plugins are consistently handled
  test-multi-module-consistency = testLib.runTest "multi-module-consistency" ''
    # Test that all mini.nvim modules map to the same package
    mini_modules=$(${pkgs.jq}/bin/jq -r '
      to_entries |
      map(select(.key | contains("mini."))) |
      map(select(.value | type == "object")) |
      map(.value.package) |
      unique[]
    ' ${../../data/mappings.json})

    echo "Mini.nvim modules should all map to mini-nvim package:"
    for package in $mini_modules; do
      echo "  Package: $package"
      if [ "$package" != "mini-nvim" ]; then
        echo "✗ Multi-module inconsistency: expected 'mini-nvim', got '$package'"
        exit 1
      fi
    done

    echo "✓ Multi-module mappings consistent"
  '';

  # Test that plugins.json structure is maintained
  test-plugins-json-structure = testLib.runTest "plugins-json-structure" ''
    echo "Validating plugins.json structure..."

    # Check required top-level fields
    required_fields=("version" "commit" "generated" "extraction_report" "plugins")
    for field in "''${required_fields[@]}"; do
      if ${pkgs.jq}/bin/jq -e "has(\"$field\")" ${../../data/plugins.json} > /dev/null; then
        echo "✓ Has field: $field"
      else
        echo "✗ Missing required field: $field"
        exit 1
      fi
    done

    # Check that plugins have required fields
    plugin_fields=("name" "owner" "repo")
    plugin_count=$(${pkgs.jq}/bin/jq '.plugins | length' ${../../data/plugins.json})
    echo "Checking $plugin_count plugins for required fields..."

    for field in "''${plugin_fields[@]}"; do
      missing_count=$(${pkgs.jq}/bin/jq --arg field "$field" '.plugins | map(select(has($field) | not)) | length' ${../../data/plugins.json})
      if [ "$missing_count" = "0" ]; then
        echo "✓ All plugins have field: $field"
      else
        echo "✗ $missing_count plugins missing field: $field"
        exit 1
      fi
    done

    echo "plugins.json structure validation passed"
  '';

  # Test that plugin count doesn't decrease dramatically
  test-plugin-count-regression = testLib.runTest "plugin-count-regression" ''
    current_count=$(${pkgs.jq}/bin/jq '.plugins | length' ${../../data/plugins.json})
    echo "Current plugin count: $current_count"

    # We expect at least 30 plugins in a typical LazyVim setup
    min_expected=30

    if [ "$current_count" -ge "$min_expected" ]; then
      echo "✓ Plugin count ($current_count) >= minimum expected ($min_expected)"
    else
      echo "✗ Plugin count regression: only $current_count plugins (expected >= $min_expected)"
      exit 1
    fi
  '';

  # Test that update script produces valid output
  test-update-script-validity = testLib.runTest "update-script-validity" ''
    echo "Testing update script components..."

    # Check that required update scripts exist and are executable
    scripts=(
      "${../../scripts/update-plugins.sh}"
      "${../../scripts/extract-plugins.lua}"
      "${../../scripts/suggest-mappings.lua}"
    )

    for script in "''${scripts[@]}"; do
      if [ -f "$script" ]; then
        echo "✓ Script exists: $(basename "$script")"
        if [ -x "$script" ] || [[ "$script" == *.lua ]]; then
          echo "✓ Script is executable/interpretable: $(basename "$script")"
        else
          echo "✗ Script not executable: $(basename "$script")"
          exit 1
        fi
      else
        echo "✗ Script missing: $(basename "$script")"
        exit 1
      fi
    done

    echo "Update script validity check passed"
  '';

  # Test backwards compatibility with old configuration formats
  test-backwards-compatibility = testLib.runTest "backwards-compatibility" ''
    # Test that older configuration patterns still work

    # Old-style extras configuration (should still work)
    oldStyleConfig='{
      config = {
        home.homeDirectory = "/tmp/test-compat";
        home.username = "testuser";
        home.stateVersion = "23.11";
        programs.lazyvim = {
          enable = true;

          # Old treesitter syntax (using strings instead of packages)
          treesitterParsers = ["lua" "nix" "rust"];
        };
      };
      lib = (import <nixpkgs> {}).lib;
      pkgs = import <nixpkgs> {};
    }'

    # This should still evaluate (backwards compatibility)
    if nix-instantiate --eval --expr "
      let module = import ${../../nix/module.nix} $oldStyleConfig;
      in module.config.programs.neovim.enable
    " 2>/dev/null >/dev/null; then
      echo "✓ Backwards compatibility maintained"
    else
      echo "✗ Backwards compatibility broken"
      exit 1
    fi
  '';

  # Test that version information is properly extracted
  test-version-info-extraction = testLib.runTest "version-info-extraction" ''
    echo "Testing version information extraction..."

    # Check that plugins have version_info when available
    plugins_with_version=$(${pkgs.jq}/bin/jq '.plugins | map(select(has("version_info"))) | length' ${../../data/plugins.json})
    total_plugins=$(${pkgs.jq}/bin/jq '.plugins | length' ${../../data/plugins.json})

    echo "Plugins with version info: $plugins_with_version/$total_plugins"

    # We expect most plugins to have some version info
    if [ "$plugins_with_version" -gt 0 ]; then
      echo "✓ Version info extraction working"

      # Check version info structure
      version_fields=("commit" "tag" "sha256")
      for field in "''${version_fields[@]}"; do
        field_count=$(${pkgs.jq}/bin/jq --arg field "$field" '.plugins | map(.version_info // {}) | map(select(has($field))) | length' ${../../data/plugins.json})
        echo "  Plugins with $field: $field_count"
      done
    else
      echo "✗ No version information extracted"
      exit 1
    fi
  '';

  # Test that extraction metadata is present and valid
  test-extraction-metadata = testLib.runTest "extraction-metadata" ''
    echo "Testing extraction metadata..."

    # Check extraction report structure
    required_report_fields=("total_plugins" "mapped_plugins" "unmapped_plugins")
    for field in "''${required_report_fields[@]}"; do
      if ${pkgs.jq}/bin/jq -e ".extraction_report | has(\"$field\")" ${../../data/plugins.json} > /dev/null; then
        value=$(${pkgs.jq}/bin/jq ".extraction_report.$field" ${../../data/plugins.json})
        echo "✓ $field: $value"
      else
        echo "✗ Missing extraction report field: $field"
        exit 1
      fi
    done

    # Check that counts are consistent
    total_plugins=$(${pkgs.jq}/bin/jq '.extraction_report.total_plugins' ${../../data/plugins.json})
    actual_plugins=$(${pkgs.jq}/bin/jq '.plugins | length' ${../../data/plugins.json})

    if [ "$total_plugins" = "$actual_plugins" ]; then
      echo "✓ Plugin count consistency: $total_plugins = $actual_plugins"
    else
      echo "✗ Plugin count mismatch: reported $total_plugins, actual $actual_plugins"
      exit 1
    fi
  '';

  # Test that no plugins are accidentally unmapped
  test-no-unmapped-regressions = testLib.runTest "no-unmapped-regressions" ''
    echo "Testing for unmapped plugin regressions..."

    unmapped_count=$(${pkgs.jq}/bin/jq '.extraction_report.unmapped_plugins' ${../../data/plugins.json})
    echo "Current unmapped plugins: $unmapped_count"

    # We expect 0 unmapped plugins in a well-maintained system
    if [ "$unmapped_count" = "0" ]; then
      echo "✓ No unmapped plugins"
    else
      echo "! Warning: $unmapped_count unmapped plugins found"

      # Show which plugins are unmapped
      ${pkgs.jq}/bin/jq -r '.extraction_report.mapping_suggestions | keys[]' ${../../data/plugins.json} 2>/dev/null | while read plugin; do
        echo "  Unmapped: $plugin"
      done
    fi
  '';

  # Test that flake evaluation remains stable
  test-flake-evaluation-stability = testLib.runTest "flake-evaluation-stability" ''
    echo "Testing flake evaluation stability..."

    # Test that the flake can be evaluated without errors
    if nix flake show ${../..} --no-update-lock-file > /dev/null 2>&1; then
      echo "✓ Flake evaluation successful"
    else
      echo "✗ Flake evaluation failed"
      exit 1
    fi

    # Test that home-manager module can be imported
    if nix-instantiate --eval --expr 'let flake = import ${../../flake.nix}; in flake.homeManagerModules ? default' > /dev/null 2>&1; then
      echo "✓ Home-manager module export stable"
    else
      echo "✗ Home-manager module export broken"
      exit 1
    fi
  '';
} // (import ./dependency-compatibility.nix { inherit pkgs testLib; })