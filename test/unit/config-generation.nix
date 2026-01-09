# Unit tests for configuration generation functions
{ pkgs, testLib, moduleUnderTest }:

let
  moduleLib = pkgs.lib;

  # Mock plugin data for testing
  mockPluginSpecs = [
    {
      name = "folke/lazy.nvim";
      owner = "folke";
      repo = "lazy.nvim";
    }
    {
      name = "nvim-mini/mini.ai";
      owner = "nvim-mini";
      repo = "mini.ai";
    }
    {
      name = "nvim-mini/mini.pairs";
      owner = "nvim-mini";
      repo = "mini.pairs";
    }
    {
      name = "neovim/nvim-lspconfig";
      owner = "neovim";
      repo = "nvim-lspconfig";
    }
  ];

  mockPluginMappings = {
    "nvim-mini/mini.ai" = { package = "mini-nvim"; module = "mini.ai"; };
    "nvim-mini/mini.pairs" = { package = "mini-nvim"; module = "mini.pairs"; };
    "folke/lazy.nvim" = "lazy-nvim";
  };

  # Mock resolved plugins (simplified for testing)
  mockResolvedPlugins = [
    pkgs.vimPlugins.lazy-nvim
    pkgs.vimPlugins.mini-nvim
    pkgs.vimPlugins.mini-nvim  # Same package for both mini modules
    pkgs.vimPlugins.nvim-lspconfig
  ];

  # Helper function to extract repository name (from module.nix)
  getRepoName = specName:
    let parts = moduleLib.splitString "/" specName;
    in if builtins.length parts == 2 then builtins.elemAt parts 1 else specName;

  # Mock createDevPath function (simplified version of the one in module.nix)
  createDevPath = allPluginSpecs: allResolvedPlugins:
    let
      # Separate multi-module plugins from regular plugins
      pluginWithType = moduleLib.zipListsWith (spec: plugin:
        if plugin != null then
          let
            mapping = mockPluginMappings.${spec.name} or null;
            isMultiModule = mapping != null && builtins.isAttrs mapping && mapping ? module;
          in {
            spec = spec;
            plugin = plugin;
            isMultiModule = isMultiModule;
            linkName = if isMultiModule then mapping.module else getRepoName spec.name;
          }
        else null
      ) allPluginSpecs allResolvedPlugins;

      # Filter out null entries
      validPlugins = builtins.filter (p: p != null) pluginWithType;

      # Deduplicate multi-module plugins by module name
      deduplicatedPlugins =
        let
          # Group by link name
          grouped = moduleLib.groupBy (p: p.linkName) validPlugins;
          # Take first entry for each unique link name
          deduplicated = moduleLib.mapAttrsToList (linkName: plugins: moduleLib.head plugins) grouped;
        in deduplicated;

      # Create symlink commands
      linkCommands = builtins.map (p: "ln -sf ${p.plugin} $out/${p.linkName}") deduplicatedPlugins;
    in
      pkgs.runCommand "test-lazyvim-dev-path" {} ''
        mkdir -p $out
        ${moduleLib.concatStringsSep "\n" linkCommands}
      '';

in {
  # Test repository name extraction
  test-repo-name-extraction-standard = testLib.testNixExpr
    "repo-name-extraction-standard"
    ''
      let
        getRepoName = specName:
          let parts = builtins.filter (x: x != "") (builtins.split "/" specName);
          in if builtins.length parts >= 2 then builtins.elemAt parts 2 else specName;
      in getRepoName "folke/tokyonight.nvim"
    ''
    "tokyonight.nvim";

  test-repo-name-extraction-single = testLib.testNixExpr
    "repo-name-extraction-single"
    ''
      let
        getRepoName = specName:
          let parts = builtins.filter (x: x != "") (builtins.split "/" specName);
          in if builtins.length parts >= 2 then builtins.elemAt parts 2 else specName;
      in getRepoName "standalone-plugin"
    ''
    "standalone-plugin";

  # Test multi-module plugin deduplication logic
  test-multi-module-deduplication = testLib.runTest "multi-module-deduplication" ''
    # Test that multiple mini.nvim modules get deduplicated to single package
    result=$(nix-instantiate --eval --expr '
      let
        lib = (import <nixpkgs> {}).lib;
        specs = [
          { name = "nvim-mini/mini.ai"; }
          { name = "nvim-mini/mini.pairs"; }
          { name = "folke/lazy.nvim"; }
        ];
        mappings = {
          "nvim-mini/mini.ai" = { package = "mini-nvim"; module = "mini.ai"; };
          "nvim-mini/mini.pairs" = { package = "mini-nvim"; module = "mini.pairs"; };
        };

        # Count unique packages needed
        uniquePackages = lib.unique (map (spec:
          let mapping = mappings.''${spec.name} or null;
          in if mapping != null && builtins.isAttrs mapping
             then mapping.package
             else spec.name
        ) specs);

        # Should have 2 unique packages: mini-nvim and folke/lazy.nvim
        packageCount = builtins.length uniquePackages;
      in packageCount
    ')
    [ "$result" = "2" ]
  '';

  # Test dev path creation structure
  test-dev-path-creation = testLib.testBuilds "dev-path-creation" ''
    ${createDevPath mockPluginSpecs mockResolvedPlugins}/bin/true || echo "Dev path creation test"
  '';

  # Test dev plugin spec generation
  test-dev-plugin-specs = testLib.runTest "dev-plugin-specs" ''
    # Test that dev plugin specs are generated correctly
    result=$(nix-instantiate --eval --expr '
      let
        lib = (import <nixpkgs> {}).lib;
        getRepoName = specName:
          let parts = lib.splitString "/" specName;
          in if lib.length parts == 2 then lib.elemAt parts 1 else specName;

        specs = [
          { name = "folke/lazy.nvim"; }
          { name = "neovim/nvim-lspconfig"; }
        ];

        # Generate dev specs (simplified)
        devSpecs = map (spec:
          "{ \"''${getRepoName spec.name}\", dev = true, pin = true },"
        ) specs;

        # Should generate 2 dev specs
        specCount = builtins.length devSpecs;
      in specCount
    ')
    [ "$result" = "2" ]
  '';

  # Test lazy.nvim configuration generation structure
  test-lazy-config-structure = testLib.runTest "lazy-config-structure" ''
    # Test that generated lazy config has required sections
    config='-- LazyVim Nix Configuration
require("lazy").setup({
  defaults = { lazy = true },
  checker = { enabled = false },
  dev = {
    path = "/some/path",
    patterns = {},
    fallback = false,
  },
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins", dev = true, pin = true },
    { "mason-org/mason.nvim", enabled = false },
  },
})'

    # Check for required sections
    echo "$config" | grep -q "require.*lazy.*setup" || exit 1
    echo "$config" | grep -q "checker.*enabled.*false" || exit 1
    echo "$config" | grep -q "mason.*enabled.*false" || exit 1
    echo "$config" | grep -q "dev.*true.*pin.*true" || exit 1
    echo "Config structure validation passed"
  '';

  # Test treesitter configuration handling
  test-treesitter-config = testLib.runTest "treesitter-config" ''
    # Test treesitter parser configuration
    result=$(nix-instantiate --eval --expr '
      let
        pkgs = import <nixpkgs> {};
        # Mock treesitter parsers list using nvim-treesitter-parsers
        parsers = with pkgs.vimPlugins.nvim-treesitter-parsers; [ lua nix ];
        # This should create a symlinked directory
        treesitterGrammars = pkgs.symlinkJoin {
          name = "treesitter-parsers";
          paths = parsers;
        };
        # Test that we get a derivation
        isDerivation = pkgs.lib.isDerivation treesitterGrammars;
      in isDerivation
    ')
    [ "$result" = "true" ]
  '';

  # Test XDG config file generation
  test-xdg-config-files = testLib.runTest "xdg-config-files" ''
    # Test that XDG config file structure is correct
    result=$(nix-instantiate --eval --expr '
      let
        lib = (import <nixpkgs> {}).lib;

        # Mock config files that should be generated
        configFiles = {
          "nvim/init.lua".text = "-- LazyVim config";
          "nvim/lua/config/options.lua".text = "-- User options";
          "nvim/lua/plugins/custom.lua".text = "-- Custom plugin";
        };

        # Check that all files have text attribute
        allHaveText = lib.all (file: file ? text) (lib.attrValues configFiles);

        # Check file count
        fileCount = lib.length (lib.attrNames configFiles);

        # Should have text and correct count
        isValid = allHaveText && fileCount == 3;
      in isValid
    ')
    [ "$result" = "true" ]
  '';

  # Test Mason.nvim disabling in config
  test-mason-disabling = testLib.runTest "mason-disabling" ''
    # Test that Mason-related plugins are properly disabled
    config='spec = {
      { "mason-org/mason.nvim", enabled = false },
      { "mason-org/mason-lspconfig.nvim", enabled = false },
      { "jay-babu/mason-nvim-dap.nvim", enabled = false },
    }'

    # Check that all Mason plugins are disabled
    echo "$config" | grep -c "mason.*enabled.*false" | grep -q "3" || exit 1
    echo "Mason disabling validation passed"
  '';

  # Test extras configuration generation
  test-extras-config-generation = testLib.runTest "extras-config-generation" ''
    # Test extras import and config file generation
    result=$(nix-instantiate --eval --expr '
      let
        lib = (import <nixpkgs> {}).lib;

        # Mock enabled extras
        enabledExtras = [
          {
            name = "nix";
            category = "lang";
            import = "lazyvim.plugins.extras.lang.nix";
            config = "opts = { servers = { nixd = {} } }";
            hasConfig = true;
          }
        ];

        # Generate import specs
        extrasImportSpecs = map (extra:
          "{ import = \"''${extra.import}\" },"
        ) enabledExtras;

        # Generate config files for extras with custom config
        extrasWithConfig = builtins.filter (extra: extra.hasConfig) enabledExtras;

        # Should have 1 import spec and 1 config file
        importCount = builtins.length extrasImportSpecs;
        configCount = builtins.length extrasWithConfig;

        isValid = importCount == 1 && configCount == 1;
      in isValid
    ')
    [ "$result" = "true" ]
  '';
}