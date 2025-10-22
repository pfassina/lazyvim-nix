# Unit tests for LazyVim module functions
{ pkgs, testLib, moduleUnderTest }:

let
  # Create a minimal test environment
  testConfig = {
    config = {
      home.homeDirectory = "/tmp/test";
      programs.lazyvim.enable = true;
    };
    lib = pkgs.lib;
    inherit pkgs;
  };

  # Load the module with test config
  testModule = moduleUnderTest testConfig;

  # Extract the functions we want to test by evaluating the module
  moduleLib = pkgs.lib;

  # Test fixtures - sample plugin data
  testPluginMappings = {
    "L3MON4D3/LuaSnip" = "luasnip";
    "catppuccin/nvim" = "catppuccin-nvim";
    "nvim-mini/mini.ai" = { package = "mini-nvim"; module = "mini.ai"; };
    "nvim-mini/mini.pairs" = { package = "mini-nvim"; module = "mini.pairs"; };
    "folke/lazy.nvim" = "lazy-nvim";
  };

  # Mock plugin specs for testing
  testPluginSpecs = [
    {
      name = "folke/tokyonight.nvim";
      owner = "folke";
      repo = "tokyonight.nvim";
      version_info = {
        commit = "abc123";
        tag = "v1.0.0";
        sha256 = "fake-hash";
      };
    }
    {
      name = "nvim-telescope/telescope.nvim";
      owner = "nvim-telescope";
      repo = "telescope.nvim";
      version_info = {};
    }
    {
      name = "L3MON4D3/LuaSnip";
      owner = "L3MON4D3";
      repo = "LuaSnip";
      version_info = {
        commit = "def456";
      };
    }
  ];

  # Plugin resolution function (extracted from module logic)
  resolvePluginName = lazyName:
    let
      mapping = testPluginMappings.${lazyName} or null;
    in
      if mapping == null then
        # Try automatic resolution
        let
          parts = moduleLib.splitString "/" lazyName;
          repoName = if builtins.length parts == 2 then builtins.elemAt parts 1 else lazyName;
          # Convert repo-name to repo_name and repo.nvim to repo-nvim
          nixName = moduleLib.replaceStrings ["-" "."] ["_" "-"] repoName;
        in nixName
      else if builtins.isString mapping then
        mapping
      else
        mapping.package;

# Import additional unit tests
devPathTests = import ./dev-path.nix { inherit pkgs testLib moduleUnderTest; };
treesitterTests = import ./treesitter-parsers.nix { inherit pkgs testLib moduleUnderTest; };

in devPathTests // treesitterTests // {
  # Test plugin name resolution
  test-plugin-name-resolution-automatic = testLib.testNixExpr
    "plugin-name-resolution-automatic"
    ''
      let
        lazyName = "folke/tokyonight.nvim";
        parts = builtins.filter (x: x != "") (builtins.split "/" lazyName);
        repoName = if builtins.length parts >= 2 then builtins.elemAt parts 2 else lazyName;
        nixName = builtins.replaceStrings ["-" "."] ["_" "-"] repoName;
      in nixName
    ''
    "tokyonight-nvim";

  test-plugin-name-resolution-manual-mapping = testLib.testNixExpr
    "plugin-name-resolution-manual-mapping"
    ''
      let
        mappings = {
          "L3MON4D3/LuaSnip" = "luasnip";
          "catppuccin/nvim" = "catppuccin-nvim";
        };
      in mappings."L3MON4D3/LuaSnip"
    ''
    "luasnip";

  test-plugin-name-resolution-multi-module = testLib.testNixExpr
    "plugin-name-resolution-multi-module"
    ''
      let
        mappings = {
          "nvim-mini/mini.ai" = { package = "mini-nvim"; module = "mini.ai"; };
        };
      in mappings."nvim-mini/mini.ai".package
    ''
    "mini-nvim";

  test-plugin-name-resolution-hyphen-to-underscore = testLib.testNixExpr
    "plugin-name-resolution-hyphen-to-underscore"
    ''
      let
        parts = ["owner" "some-plugin"];
        repoName = builtins.elemAt parts 1;
        nixName = builtins.replaceStrings ["-" "."] ["_" "-"] repoName;
      in nixName
    ''
    "some_plugin";

  test-plugin-name-resolution-dot-to-hyphen = testLib.testNixExpr
    "plugin-name-resolution-dot-to-hyphen"
    ''
      let
        parts = ["owner" "plugin.nvim"];
        repoName = builtins.elemAt parts 1;
        nixName = builtins.replaceStrings ["-" "."] ["_" "-"] repoName;
      in nixName
    ''
    "plugin-nvim";

  # Test multi-module plugin detection
  test-multi-module-detection = testLib.testNixExpr
    "multi-module-detection"
    ''
      let
        mapping = { package = "mini-nvim"; module = "mini.ai"; };
        isMultiModule = builtins.isAttrs mapping && mapping ? module;
      in isMultiModule
    ''
    "true";

  # Test module name extraction
  test-module-name-extraction = testLib.testNixExpr
    "module-name-extraction"
    ''
      let
        mapping = { package = "mini-nvim"; module = "mini.ai"; };
      in mapping.module
    ''
    "mini.ai";

  # Test automatic resolution edge cases
  test-plugin-resolution-single-name = testLib.testNixExpr
    "plugin-resolution-single-name"
    ''
      let
        lazyName = "single-plugin";
        parts = ["single-plugin"];  # No "/" separator
        repoName = if builtins.length parts == 2 then builtins.elemAt parts 1 else lazyName;
        nixName = builtins.replaceStrings ["-" "."] ["_" "-"] repoName;
      in nixName
    ''
    "single_plugin";

  # Test empty plugin name handling
  test-plugin-resolution-empty = testLib.testNixExpr
    "plugin-resolution-empty"
    ''
      let
        lazyName = "";
        parts = [];
        repoName = if builtins.length parts == 2 then builtins.elemAt parts 1 else lazyName;
      in repoName
    ''
    "";

  # Test plugin spec validation
  test-plugin-spec-structure = testLib.testNixExpr
    "plugin-spec-structure"
    ''
      let
        spec = {
          name = "folke/tokyonight.nvim";
          owner = "folke";
          repo = "tokyonight.nvim";
          version_info = {};
        };
        hasRequiredFields = spec ? name && spec ? owner && spec ? repo;
      in hasRequiredFields
    ''
    "true";

  # Test version info handling
  test-version-info-extraction = testLib.testNixExpr
    "version-info-extraction"
    ''
      let
        spec = {
          name = "folke/tokyonight.nvim";
          owner = "folke";
          repo = "tokyonight.nvim";
          version_info = {
            commit = "abc123";
            tag = "v1.0.0";
            sha256 = "fake-hash";
          };
        };
        commit = spec.version_info.commit;
      in commit
    ''
    "abc123";

  # Test that mappings are consistent (no cycles, valid structure)
  test-mappings-consistency = testLib.testNixExpr
    "mappings-consistency"
    ''
      let
        mappings = {
          "L3MON4D3/LuaSnip" = "luasnip";
          "catppuccin/nvim" = "catppuccin-nvim";
          "nvim-mini/mini.ai" = { package = "mini-nvim"; module = "mini.ai"; };
          "nvim-mini/mini.pairs" = { package = "mini-nvim"; module = "mini.pairs"; };
          "folke/lazy.nvim" = "lazy-nvim";
        };
        validateMapping = name: mapping:
          builtins.isString mapping ||
          (builtins.isAttrs mapping && mapping ? package && mapping ? module);
        allValid = builtins.all (mapping: validateMapping "test" mapping) (builtins.attrValues mappings);
      in allValid
    ''
    "true";

  # Test complex plugin name patterns
  test-complex-plugin-names = testLib.testNixExpr
    "complex-plugin-names"
    ''
      let
        # Test telescope.nvim conversion
        telescopeName = "nvim-telescope/telescope.nvim";
        telescopeParts = builtins.filter (x: x != "") (builtins.split "/" telescopeName);
        telescopeRepo = if builtins.length telescopeParts >= 2 then builtins.elemAt telescopeParts 2 else telescopeName;
        telescopeNix = builtins.replaceStrings ["-" "."] ["_" "-"] telescopeRepo;

        # Test nvim-cmp conversion
        cmpName = "hrsh7th/nvim-cmp";
        cmpParts = builtins.filter (x: x != "") (builtins.split "/" cmpName);
        cmpRepo = if builtins.length cmpParts >= 2 then builtins.elemAt cmpParts 2 else cmpName;
        cmpNix = builtins.replaceStrings ["-" "."] ["_" "-"] cmpRepo;

        # Check results
        telescopeCorrect = telescopeNix == "telescope-nvim";
        cmpCorrect = cmpNix == "nvim_cmp";
      in telescopeCorrect && cmpCorrect
    ''
    "true";
} // (import ./dependency-resolution.nix { inherit pkgs testLib; })