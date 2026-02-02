# LazyVim Nix module - Main entry point
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.lazyvim;

  # Import all library modules
  dataLib = import ./lib/data-loading.nix { inherit lib pkgs; };
  pluginLib = import ./lib/plugin-resolution.nix {
    inherit lib pkgs;
    pluginMappings = dataLib.pluginMappings;
    ignoreBuildNotifications = cfg.ignoreBuildNotifications;
  };
  devPathLib = import ./lib/dev-path.nix {
    inherit lib pkgs;
    pluginMappings = dataLib.pluginMappings;
  };
  treesitterLib = import ./lib/treesitter.nix {
    inherit lib pkgs;
    treesitterMappings = dataLib.treesitterMappings;
    extractLang = dataLib.extractLang;
    ignoreBuildNotifications = cfg.ignoreBuildNotifications;
  };
  dependenciesLib = import ./lib/dependencies.nix {
    inherit lib pkgs;
    dependencies = dataLib.dependencies;
    ignoreBuildNotifications = cfg.ignoreBuildNotifications;
  };
  configLib = import ./lib/config-generation.nix { inherit lib; };
  fileLib = import ./lib/file-scanning.nix { inherit lib pkgs config; };

  # Helper function to collect enabled extras
  getEnabledExtras = extrasConfig:
    let
      processCategory = categoryName: categoryExtras:
        let
          enabledInCategory = lib.filterAttrs (extraName: extraConfig:
            extraConfig.enable or false
          ) categoryExtras;
        in
          lib.mapAttrsToList (extraName: extraConfig:
            let
              metadata = dataLib.extrasMetadata.${categoryName}.${extraName} or null;
            in
              if metadata != null then {
                inherit (metadata) name category import;
                config = extraConfig.config or "";
                hasConfig = (extraConfig.config or "") != "";
              } else
                null
          ) enabledInCategory;

      allCategories = lib.mapAttrsToList processCategory extrasConfig;
      flattenedExtras = lib.flatten allCategories;
      validExtras = lib.filter (x: x != null) flattenedExtras;
    in
      validExtras;

  # Get list of enabled extras
  enabledExtras = if cfg.enable then getEnabledExtras (cfg.extras or {}) else [];

  # Enabled extra identifiers (category.name) for downstream tooling
  enabledExtraNames = map (extra: "${extra.category}.${extra.name}") enabledExtras;

  # Derive automatic treesitter parsers
  automaticTreesitterParsers = treesitterLib.automaticTreesitterParsers cfg enabledExtraNames;

  # Calculate system dependencies
  systemPackages = dependenciesLib.systemPackages cfg enabledExtraNames;

  # Scan for user plugins from the default LazyVim config directory
  userPlugins = if cfg.enable then
    fileLib.scanUserPlugins "${config.home.homeDirectory}/.config/${cfg.appName}"
  else [];

  # Filter plugins by category: only build core plugins by default
  corePlugins = builtins.filter (p: p.is_core or false) (dataLib.pluginData.plugins or []);

  # Get plugins from enabled extras only
  extrasPlugins =
    let
      # Get list of enabled extras files (e.g., ["extras.ai.copilot", "extras.lang.python"])
      enabledExtrasFiles = map (extra: "extras.${extra.category}.${extra.name}") enabledExtras;

      # Check if a plugin belongs to an enabled extra
      isExtraEnabled = plugin: builtins.elem (plugin.source_file or "") enabledExtrasFiles;

      # Get all non-core plugins (i.e., extras plugins)
      allExtrasPlugins = builtins.filter (p: !(p.is_core or false)) (dataLib.pluginData.plugins or []);
    in
      # Only include extras that are enabled
      builtins.filter isExtraEnabled allExtrasPlugins;

  # Merge core plugins with enabled extras plugins and user plugins
  allPluginSpecs = corePlugins ++ extrasPlugins ++ userPlugins;

  # Resolve all plugins using the smart resolver
  resolvedPlugins = map (pluginLib.resolvePlugin cfg) allPluginSpecs;

  # Extract the resolved nvim-treesitter plugin for query file linking
  # Must come from the same resolved list to match the parser strategy
  resolvedTreesitterPlugin =
    let
      tsPlugins = lib.zipListsWith (spec: plugin:
        if spec.name == "nvim-treesitter/nvim-treesitter" then plugin else null
      ) allPluginSpecs resolvedPlugins;
      found = lib.findFirst (p: p != null) null tsPlugins;
    in
      if found != null then found else pkgs.vimPlugins.nvim-treesitter;

  # Create the dev path with proper symlinks
  devPath = devPathLib.createDevPath allPluginSpecs resolvedPlugins;

  # Generate dev plugin specs for available plugins
  availableDevSpecs = devPathLib.generateDevPluginSpecs devPathLib allPluginSpecs resolvedPlugins;

  # Generate extras import statements
  extrasImportSpecs = configLib.extrasImportSpecs enabledExtras;

  # Treesitter configuration
  # Select grammar source based on pluginSource strategy:
  # - "latest": Build parsers from source to match nvim-treesitter version
  # - "nixpkgs": Use nixpkgs grammarPlugins (current behavior)
  treesitterGrammars =
    if cfg.pluginSource == "latest" && treesitterLib.hasParserRevisions then
      treesitterLib.treesitterGrammarsFromSource automaticTreesitterParsers
    else
      treesitterLib.treesitterGrammars automaticTreesitterParsers;

  # Generate lazy.nvim configuration by patching the official LazyVim starter
  lazyConfig = configLib.lazyConfig {
    starterLua = dataLib.starterLua;
    starterVersion = dataLib.starterVersion;
    inherit devPath extrasImportSpecs availableDevSpecs;
  };

  # Generate extras config override files
  extrasConfigFiles = configLib.extrasConfigFiles enabledExtras cfg.appName;

  # Scan config files if provided
  scannedFiles = fileLib.scanConfigFiles cfg.configFiles cfg.appName;

  # Detect conflicts and ensure no conflicts exist
  conflictChecks = fileLib.detectConflicts cfg scannedFiles;
  _ = if cfg.enable then conflictChecks else null;

in {
  # Import module options
  options.programs.lazyvim = import ./options.nix { inherit lib; };

  config = mkIf cfg.enable {
    # Force evaluation of conflict checks (this will throw if conflicts exist)
    _module.args._conflictCheck = conflictChecks;

    # Ensure neovim is enabled
    programs.neovim = {
      enable = true;
      package = pkgs.neovim-unwrapped;

      withNodeJs = true;
      withPython3 = true;
      withRuby = false;

      # Add all required packages
      extraPackages = cfg.extraPackages ++ systemPackages;

      # Add lazy.nvim as a plugin
      plugins = [ pkgs.vimPlugins.lazy-nvim ];
    };

    # Link treesitter parsers to the correct data directory
    # nvim-treesitter expects parsers at stdpath('data')/site/parser
    xdg.dataFile = {
      "${cfg.appName}/site/parser" = mkIf (automaticTreesitterParsers != []) {
        source = "${treesitterGrammars}/parser";
      };
      "${cfg.appName}/site/queries" = mkIf (automaticTreesitterParsers != []) {
        source = "${resolvedTreesitterPlugin}/runtime/queries";
      };
    };

    # Create LazyVim configuration
    xdg.configFile = {
      "${cfg.appName}/init.lua".text = lazyConfig;

      # LazyVim config files - use configFiles if available, otherwise use string options
      "${cfg.appName}/lua/config/autocmds.lua" = mkIf (
        scannedFiles.configFiles ? autocmds || cfg.config.autocmds != ""
      ) (
        if scannedFiles.configFiles ? autocmds then
          { source = scannedFiles.configFiles.autocmds.file; }
        else
          {
            text = ''
              -- User autocmds configured via Nix
              ${cfg.config.autocmds}
            '';
          }
      );

      "${cfg.appName}/lua/config/keymaps.lua" = mkIf (
        scannedFiles.configFiles ? keymaps || cfg.config.keymaps != ""
      ) (
        if scannedFiles.configFiles ? keymaps then
          { source = scannedFiles.configFiles.keymaps.file; }
        else
          {
            text = ''
              -- User keymaps configured via Nix
              ${cfg.config.keymaps}
            '';
          }
      );

      "${cfg.appName}/lua/config/options.lua" = mkIf (
        scannedFiles.configFiles ? options || cfg.config.options != ""
      ) (
        if scannedFiles.configFiles ? options then
          { source = scannedFiles.configFiles.options.file; }
        else
          {
            text = ''
              -- User options configured via Nix
              ${cfg.config.options}
            '';
          }
      );

    }
    # Generate plugin configuration files from both sources
    // (lib.mapAttrs' (name: content:
      lib.nameValuePair "${cfg.appName}/lua/plugins/${name}.lua" {
        text = ''
          -- Plugin configuration for ${name} (configured via Nix)
          ${content}
        '';
      }
    ) cfg.plugins)
    # Add plugin files from configFiles
    // (lib.mapAttrs' (name: fileInfo:
      lib.nameValuePair fileInfo.targetPath {
        source = fileInfo.file;
      }
    ) scannedFiles.pluginFiles)
    # Generate extras config override files
    // extrasConfigFiles
    # Add default plugin file when no plugins are defined to prevent LazyVim error
    // (
      let
        hasUserPlugins = cfg.plugins != {} || scannedFiles.pluginFiles != {};
      in
        optionalAttrs (!hasUserPlugins) {
          "${cfg.appName}/lua/plugins/_lazyvim_nix_default.lua" = {
            text = ''
              -- Default plugin specification to ensure plugins directory is valid
              -- This prevents "No specs found for module 'plugins'" error
              return {}
            '';
          };
        }
    )
    # Disable LazyVim's treesitter healthcheck - Nix provides pre-built parsers
    // {
      "${cfg.appName}/lua/plugins/_lazyvim_nix_healthcheck.lua" = {
        text = ''
          -- [NIX] Disable treesitter healthcheck - parsers are pre-built by Nix
          -- LazyVim's healthcheck expects tree-sitter CLI and C compiler which aren't needed
          vim.api.nvim_create_autocmd("User", {
            pattern = "VeryLazy",
            once = true,
            callback = function()
              local ok, ts = pcall(require, "lazyvim.util.treesitter")
              if ok and ts then
                ts.check = function()
                  return true, { ["nix"] = true }
                end
              end
            end,
          })
          return {}
        '';
      };
    };
  };
}
