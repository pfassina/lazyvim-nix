{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.lazyvim;

  # Load plugin data and mappings
  pluginData = pkgs.lazyvimPluginData or (builtins.fromJSON (builtins.readFile ../data/plugins.json));
  pluginMappings = pkgs.lazyvimPluginMappings or (builtins.fromJSON (builtins.readFile ../data/mappings.json));

  # Load extras metadata
  extrasMetadata = pkgs.lazyvimExtrasMetadata or (builtins.fromJSON (builtins.readFile ../data/extras.json));

  # Load treesitter parser mappings
  treesitterMappings = pkgs.lazyvimTreesitterMappings or (builtins.fromJSON (builtins.readFile ../data/treesitter.json));

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
              metadata = extrasMetadata.${categoryName}.${extraName} or null;
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

  # Derive automatic treesitter parsers
  automaticTreesitterParsers = if cfg.enable then
    let
      # Get enabled extra names in "category.name" format for lookup
      enabledExtraNames = lib.flatten (lib.mapAttrsToList (category: extras:
        lib.mapAttrsToList (name: extraConfig:
          lib.optional (extraConfig.enable or false) "${category}.${name}"
        ) extras
      ) (cfg.extras or {}));

      # Core parsers are always included
      coreParsers = treesitterMappings.core or [];

      # Extra parsers based on enabled extras
      extraParsers = lib.flatten (map (extraName:
        treesitterMappings.extras.${extraName} or []
      ) enabledExtraNames);

      # Combine and deduplicate all parsers (keep as names, not packages)
      allParsers = lib.unique (coreParsers ++ extraParsers ++ (map extractLang cfg.treesitterParsers));
    in
      allParsers
  else
    map extractLang cfg.treesitterParsers;



  # Helper function to build a vim plugin from source
  buildVimPluginFromSource = pluginSpec:
    let
      owner = pluginSpec.owner or (builtins.elemAt (lib.splitString "/" pluginSpec.name) 0);
      repo = pluginSpec.repo or (builtins.elemAt (lib.splitString "/" pluginSpec.name) 1);
      versionInfo = pluginSpec.version_info or {};

      # Determine which version to build
      # Priority: lazyvim_version > tag > latest_version > commit
      rev = if versionInfo ? lazyvim_version && versionInfo.lazyvim_version != null && versionInfo.lazyvim_version != "*" then
              versionInfo.lazyvim_version
            else if versionInfo ? tag && versionInfo.tag != null then
              versionInfo.tag
            else if versionInfo ? latest_version && versionInfo.latest_version != null then
              versionInfo.latest_version
            else if versionInfo ? commit && versionInfo.commit != null && versionInfo.commit != "*" then
              versionInfo.commit
            else "HEAD";

      # SHA256 hash is required for fetchFromGitHub
      sha256 = versionInfo.sha256 or null;

      # For latest/HEAD, use fetchGit which doesn't require a hash
      # For pinned versions with sha256, use fetchFromGitHub
      src = if rev == "HEAD" || sha256 == null then
        builtins.fetchGit ({
          url = "https://github.com/${owner}/${repo}";
          shallow = true;
        } // lib.optionalAttrs (rev != "HEAD") {
          ref = rev;
        })
      else
        pkgs.fetchFromGitHub {
          inherit owner repo rev sha256;
        };
    in
      if owner != null && repo != null then
        pkgs.vimUtils.buildVimPlugin {
          pname = repo;
          version = rev;
          inherit src;
          doCheck = false;  # Disable require checks that may fail
          meta = {
            description = "LazyVim plugin: ${pluginSpec.name}";
            homepage = "https://github.com/${owner}/${repo}";
          };
        }
      else
        null;

  # Helper function to resolve plugin names
  resolvePluginName = lazyName:
    let
      mapping = pluginMappings.${lazyName} or null;
    in
      if mapping == null then
        # Try automatic resolution with multiple patterns
        let
          parts = lib.splitString "/" lazyName;
          repoName = if length parts == 2 then elemAt parts 1 else lazyName;

          # Pattern 1: owner/name.nvim -> name-nvim (most common)
          pattern1 = if lib.hasSuffix ".nvim" repoName then
            "${lib.removeSuffix ".nvim" repoName}-nvim"
          else null;

          # Pattern 2: owner/name-nvim -> name-nvim
          pattern2 = if lib.hasSuffix "-nvim" repoName then
            repoName
          else null;

          # Pattern 3: owner/nvim-name -> nvim-name
          pattern3 = if lib.hasPrefix "nvim-" repoName then
            repoName
          else null;

          # Pattern 4: owner/name -> name (convert dashes to underscores)
          pattern4 = lib.replaceStrings ["-" "."] ["_" "_"] repoName;

          # Try patterns in order of preference
          nixName =
            if pattern1 != null then pattern1
            else if pattern2 != null then pattern2
            else if pattern3 != null then pattern3
            else pattern4;
        in nixName
      else if builtins.isString mapping then
        mapping
      else
        mapping.package;

  # Helper function to create dev path with proper symlinks for all plugins
  createDevPath = allPluginSpecs: allResolvedPlugins:
    let
      # Extract repository name from plugin spec (e.g., "owner/repo.nvim" -> "repo.nvim")
      getRepoName = specName:
        let parts = lib.splitString "/" specName;
        in if length parts == 2 then elemAt parts 1 else specName;

      # Separate multi-module plugins from regular plugins
      pluginWithType = lib.zipListsWith (spec: plugin:
        if plugin != null then
          let
            mapping = pluginMappings.${spec.name} or null;
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
      validPlugins = filter (p: p != null) pluginWithType;

      # Deduplicate multi-module plugins by module name
      deduplicatedPlugins =
        let
          # Group by link name
          grouped = lib.groupBy (p: p.linkName) validPlugins;
          # Take first entry for each unique link name
          deduplicated = lib.mapAttrsToList (linkName: plugins: lib.head plugins) grouped;
        in deduplicated;

      # Create symlink commands
      linkCommands = map (p: "ln -sf ${p.plugin} $out/${p.linkName}") deduplicatedPlugins;
    in
      pkgs.runCommand "lazyvim-dev-path" {} ''
        mkdir -p $out
        ${lib.concatStringsSep "\n" linkCommands}
      '';

  # Function to scan user plugins from LazyVim configuration
  scanUserPlugins = config_path:
    let
      # Use Nix to call the Lua scanner script
      scanResult = pkgs.runCommand "scan-user-plugins" {
        buildInputs = [ pkgs.lua pkgs.neovim ];
      } ''
        # Copy scanner script to build directory
        cp ${../scripts/scan-user-plugins.lua} scan-user-plugins.lua

        # Create a simple Lua runner script
        cat > run-scanner.lua << 'EOF'
        -- Initialize vim.loop for the scanner
        _G.vim = _G.vim or {}
        vim.loop = vim.loop or require('luv')

        -- Load the scanner
        local scanner = dofile('scan-user-plugins.lua')

        -- Scan for user plugins
        local user_plugins = scanner.scan_user_plugins("${config_path}")

        -- Output as JSON-like format for Nix to parse
        local function to_json_array(plugins)
          local result = "["
          for i, plugin in ipairs(plugins) do
            if i > 1 then result = result .. "," end
            result = result .. string.format(
              '{"name":"%s","owner":"%s","repo":"%s","source_file":"%s","user_plugin":true}',
              plugin.name, plugin.owner, plugin.repo, plugin.source_file
            )
          end
          result = result .. "]"
          return result
        end

        -- Write result
        local file = io.open("$out", "w")
        file:write(to_json_array(user_plugins))
        file:close()
        EOF

        # Run the scanner if config path exists
        if [ -d "${config_path}" ]; then
          lua run-scanner.lua 2>/dev/null || echo "[]" > $out
        else
          echo "[]" > $out
        fi
      '';
      userPluginsJson = builtins.readFile scanResult;
      userPluginsList = if userPluginsJson == "[]" then [] else builtins.fromJSON userPluginsJson;
    in
      userPluginsList;

  # Scan for user plugins from the default LazyVim config directory
  userPlugins = if cfg.enable then
    scanUserPlugins "${config.home.homeDirectory}/.config/nvim"
  else [];

  # Filter plugins by category: only build core plugins by default
  corePlugins = builtins.filter (p: p.is_core or false) (pluginData.plugins or []);

  # Get plugins from enabled extras only
  extrasPlugins =
    let
      # Get list of enabled extras files (e.g., ["extras.ai.copilot", "extras.lang.python"])
      enabledExtrasFiles = map (extra: "extras.${extra.category}.${extra.name}") enabledExtras;

      # Check if a plugin belongs to an enabled extra
      isExtraEnabled = plugin: builtins.elem (plugin.source_file or "") enabledExtrasFiles;

      # Get all non-core plugins (i.e., extras plugins)
      allExtrasPlugins = builtins.filter (p: !(p.is_core or false)) (pluginData.plugins or []);
    in
      # Only include extras that are enabled
      builtins.filter isExtraEnabled allExtrasPlugins;

  # Merge core plugins with enabled extras plugins and user plugins
  allPluginSpecs = corePlugins ++ extrasPlugins ++ userPlugins;

  # Note: Multi-module plugin expansion is handled in the final package building

  # Enhanced plugin resolver with version-aware strategy
  resolvePlugin = pluginSpec:
    let
      nixName = resolvePluginName pluginSpec.name;
      nixPlugin = pkgs.vimPlugins.${nixName} or null;
      versionInfo = pluginSpec.version_info or {};

      # Extract version information
      lazyvimVersion = versionInfo.lazyvim_version or null;
      lazyvimVersionType = versionInfo.lazyvim_version_type or null;
      latestVersion = versionInfo.latest_version or null;
      tagVersion = versionInfo.tag or null;
      commitVersion = versionInfo.commit or null;
      branchVersion = versionInfo.branch or null;
      nixpkgsVersion = if nixPlugin != null then
        nixPlugin.src.rev or nixPlugin.version or null
      else null;

      # Determine LazyVim-specified source requirements
      lazyvimRequiresBranch = lazyvimVersionType == "branch";
      lazyvimRequiresNoReleases = lazyvimVersion == false; # version = false
      lazyvimHasSpecificCommit = lazyvimVersionType == "commit";
      lazyvimHasSpecificTag = lazyvimVersionType == "tag";

      # Determine target version based on LazyVim specifications
      # Priority: respect LazyVim's exact specifications first
      targetVersion = if lazyvimVersion != null && lazyvimVersion != "*" && lazyvimVersion != false then
        lazyvimVersion
      else if tagVersion != null then
        tagVersion
      else if latestVersion != null then
        latestVersion
      else
        commitVersion;

      # Check if versions match (but respect LazyVim branch/version=false requirements)
      nixpkgsMatchesTarget =
        # Never use nixpkgs if LazyVim requires a specific branch
        if lazyvimRequiresBranch then false
        # Never use nixpkgs if LazyVim specifies version = false (no releases)
        else if lazyvimRequiresNoReleases then false
        # For other cases, check if versions match
        else targetVersion != null && nixpkgsVersion != null &&
             (targetVersion == nixpkgsVersion || targetVersion == "*");

      # Decision logic based on strategy
      useNixpkgs =
        if cfg.pluginSource == "latest" then
          # Strategy "latest": Follow LazyVim specifications exactly
          # Use nixpkgs only if it matches AND LazyVim doesn't require special handling
          nixpkgsMatchesTarget && !lazyvimRequiresBranch && !lazyvimRequiresNoReleases
        else  # cfg.pluginSource == "nixpkgs"
          # Strategy "nixpkgs": Prefer nixpkgs but respect LazyVim branch/version=false requirements
          if lazyvimRequiresBranch || lazyvimRequiresNoReleases then
            # LazyVim has specific source requirements, must build from source
            false
          else if targetVersion != null && targetVersion != "*" then
            # If we have a specific version, use nixpkgs only if it matches
            nixpkgsMatchesTarget
          else
            # No specific version required, use nixpkgs if available
            nixPlugin != null;

      # Build from source if we need a specific version not in nixpkgs
      needsSourceBuild = targetVersion != null && !useNixpkgs && versionInfo.sha256 != null;

      # Build source plugin with the target version
      sourcePlugin = if needsSourceBuild then
        buildVimPluginFromSource pluginSpec
      else null;

      # Final plugin selection
      finalPlugin =
        if useNixpkgs && nixPlugin != null then
          nixPlugin
        else if sourcePlugin != null then
          sourcePlugin
        else if nixPlugin != null then
          nixPlugin  # Fallback to nixpkgs even if version doesn't match
        else
          null;

      # Enhanced debug trace
      debugTrace =
        if builtins.elem pluginSpec.name ["LazyVim/LazyVim" "folke/lazy.nvim"] then
          builtins.trace "${pluginSpec.name}: Using ${
            if useNixpkgs then "nixpkgs (${if nixpkgsVersion != null then nixpkgsVersion else "unknown"})"
            else if sourcePlugin != null then "source (${if targetVersion != null then targetVersion else "latest"})"
            else "fallback nixpkgs"
          }"
        else
          (x: x);
    in
      debugTrace (
        if finalPlugin == null then
          builtins.trace "Warning: Could not resolve plugin ${pluginSpec.name}" null
        else
          finalPlugin
      );

  # Resolve all plugins using the smart resolver
  resolvedPlugins = map resolvePlugin allPluginSpecs;
  
  # Create the dev path with proper symlinks
  devPath = createDevPath allPluginSpecs resolvedPlugins;
  
  # Extract repository name from plugin spec (needed for config generation)
  getRepoName = specName:
    let parts = lib.splitString "/" specName;
    in if length parts == 2 then elemAt parts 1 else specName;
  
  # Generate dev plugin specs for available plugins
  devPluginSpecs = lib.zipListsWith (spec: plugin:
    if plugin != null &&
       spec.name != "nvim-treesitter/nvim-treesitter" &&
       spec.name != "nvim-treesitter/nvim-treesitter-textobjects" then
      ''{ "${getRepoName spec.name}", dev = true, pin = true },''
    else
      null
  ) allPluginSpecs resolvedPlugins;

  # Filter out null entries
  availableDevSpecs = filter (s: s != null) devPluginSpecs;

  # Generate extras import statements
  extrasImportSpecs = map (extra:
    ''{ import = "${extra.import}" },''
  ) enabledExtras;

  # Generate extras config override files for extras with custom config
  extrasWithConfig = filter (extra: extra.hasConfig) enabledExtras;

  extrasConfigFiles = lib.listToAttrs (map (extra:
    lib.nameValuePair
      "nvim/lua/plugins/extras-${extra.category}-${extra.name}.lua"
      {
        text = ''
          -- Extra configuration override for ${extra.category}/${extra.name} (configured via Nix)
          -- This file overrides the default configuration from the LazyVim extra
          ${extra.config}
        '';
      }
  ) extrasWithConfig);

  # Generate lazy.nvim configuration
  lazyConfig = ''
    -- LazyVim Nix Configuration
    -- This file is auto-generated by the lazyvim-nix flake
    
    local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
    if not vim.loop.fs_stat(lazypath) then
      vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable",
        lazypath,
      })
    end
    vim.opt.rtp:prepend(lazypath)
    
    -- Configure lazy.nvim to use pre-fetched plugins
    require("lazy").setup({
      defaults = { lazy = true },
      checker = { enabled = false },  -- Disable update checker since Nix manages versions
      change_detection = { notify = false },  -- Disable config change notifications
      dev = {
        path = "${devPath}",
        patterns = {},  -- Don't automatically match, use explicit dev = true
        fallback = false,
      },
      spec = {
        { "LazyVim/LazyVim", import = "lazyvim.plugins", dev = true, pin = true },
        -- LazyVim extras
        ${concatStringsSep "\n        " extrasImportSpecs}
        -- Disable Mason.nvim in Nix environment
        { "mason-org/mason.nvim", enabled = false },
        { "mason-org/mason-lspconfig.nvim", enabled = false },
        { "jay-babu/mason-nvim-dap.nvim", enabled = false },
        -- Configure treesitter to work with Nix-managed parsers
        {
          "nvim-treesitter/nvim-treesitter",
          -- Parser compilation is skipped when using Nix
          build = false,
          opts = function(_, opts)
            opts.auto_install = false
            opts.ensure_installed = {}
            return opts
          end,
          config = function(_, opts)

            local TS = require("nvim-treesitter")
            local LazyVimUtil = require("lazyvim.util")

            -- Mock TS.get_installed to bypass the installation checks
            -- See nvim-treesitter/lua/nvim-treesitter/config.lua#L42-L58
            local _ts_install = TS.get_installed
            TS.get_installed = function()
              return {}
            end

            -- Mock LazyVimUtil.treesitter.get_installed() to populate M._installed
            -- from the buildtime parser list. This ensures M._installed is
            -- populated correctly for autocmd functionality
            -- See LazyVim/lua/lazyvim/util/treesitter.lua#L7-L17
            local _lazyvim_install = LazyVimUtil.treesitter.get_installed

            -- Nix-managed parser list (extracted from treesitterParsers option)
            local nix_parsers = { ${treesitterLangList} }

            LazyVimUtil.treesitter.get_installed = function(update)
              if update then
                LazyVimUtil.treesitter._installed = {}
                LazyVimUtil.treesitter._queries = {}
                for _, lang in ipairs(nix_parsers) do
                  LazyVimUtil.treesitter._installed[lang] = true
                end
              end
              return LazyVimUtil.treesitter._installed or {}
            end

            -- Find and call LazyVim's default config
            -- This will:
            -- 1. Pass the version check (TS.get_installed returns empty)
            -- 2. Setup treesitter with our opts
            -- 3. Skip parser installation (ensure_installed is empty)
            -- 4. Populate M._installed with Nix parsers (our LazyVim mock)
            -- 5. Create autocmds for highlighting, indents, folds
            local treesitter_plugins = require("lazyvim.plugins.treesitter")
            local config_fn = nil

            -- Search for first nvim-treesitter plugin spec by identifier
            for _, spec in ipairs(treesitter_plugins) do
              if spec[1] == "nvim-treesitter/nvim-treesitter" and
                 type(spec.config) == "function" then
                config_fn = spec.config
                break
              end
            end

            if not config_fn then
              error("Failed to find nvim-treesitter config in lazyvim.plugins.treesitter")
            else
              config_fn(_, opts)
            end

            -- Restore pre-mock references
            LazyVimUtil.treesitter.get_installed = _lazyvim_install
            if _ts_install then
              TS.get_installed = _ts_install
            else
              TS.get_installed = nil
            end
          end,
          dev = true,
          pin = true,
        },
        -- Mark available plugins as dev = true
        ${concatStringsSep "\n        " availableDevSpecs}
        -- User plugins
        { import = "plugins" },
      },
      performance = {
        rtp = {
          disabled_plugins = {
            "gzip",
            "matchit",
            "matchparen",
            "netrwPlugin",
            "tarPlugin",
            "tohtml",
            "tutor",
            "zipPlugin",
          },
        },
      },
    })
    
  '';

  # Extract language names from treesitter parser packages for Lua config
  # automaticTreesitterParsers now contains parser names directly
  treesitterLangNames = automaticTreesitterParsers;

  # Generate Lua array string for parser list
  treesitterLangList = lib.concatStringsSep ", " (map (l: ''"${l}"'') treesitterLangNames);

  # Treesitter configuration - use nvim-treesitter's grammar plugins directly
  treesitterGrammars = let
    # automaticTreesitterParsers now contains parser names, not packages
    parserNames = automaticTreesitterParsers;

    # Use nvim-treesitter's grammar plugins which are compatible
    parserPackages = lib.filter (pkg: pkg != null) (map (parserName:
      pkgs.vimPlugins.nvim-treesitter.grammarPlugins.${parserName} or (
        builtins.trace "Warning: treesitter parser '${parserName}' not found in nvim-treesitter grammar plugins" null
      )
    ) parserNames);

    parsers = pkgs.symlinkJoin {
      name = "treesitter-parsers";
      paths = parserPackages;
    };
  in parsers;

  # Helper function to scan config files from a directory
  scanConfigFiles = configPath:
    if configPath == null then
      { configFiles = {}; pluginFiles = {}; }
    else if !builtins.pathExists configPath then
      builtins.throw "configFiles path does not exist: ${toString configPath}"
    else
      let
        # Get all files in the directory recursively
        allFiles = lib.filesystem.listFilesRecursive configPath;

        # Helper to get relative path from configPath
        getRelativePath = file:
          let
            absPath = toString file;
            basePath = toString configPath;
            # Remove the base path and leading slash
            relPath = lib.removePrefix (basePath + "/") absPath;
          in relPath;

        # Filter and categorize Lua files
        processFile = file:
          let
            relPath = getRelativePath file;
            # Check if it's a Lua file
            isLua = lib.hasSuffix ".lua" relPath;

            # Determine the target path based on the source structure
            # Support both "lua/config/file.lua" and "config/file.lua" layouts
            targetPath =
              if lib.hasPrefix "lua/" relPath then
                # Already has lua/ prefix, use as-is
                "nvim/${relPath}"
              else if lib.hasPrefix "config/" relPath then
                # config/ at root, add lua/ prefix
                "nvim/lua/${relPath}"
              else if lib.hasPrefix "plugins/" relPath then
                # plugins/ at root, add lua/ prefix
                "nvim/lua/${relPath}"
              else
                # Other structure - put under lua/
                "nvim/lua/${relPath}";

            # Determine file category for conflict detection
            category =
              if lib.hasSuffix "/config/keymaps.lua" targetPath then "keymaps"
              else if lib.hasSuffix "/config/options.lua" targetPath then "options"
              else if lib.hasSuffix "/config/autocmds.lua" targetPath then "autocmds"
              else if lib.hasInfix "/plugins/" targetPath then
                let
                  # Extract plugin file name (e.g., "colorscheme" from "nvim/lua/plugins/colorscheme.lua")
                  pluginName = lib.removeSuffix ".lua" (baseNameOf relPath);
                in "plugin:${pluginName}"
              else null;
          in
            if isLua && category != null then
              { inherit file targetPath category; }
            else
              null;

        # Process all files and filter out nulls
        processedFiles = lib.filter (f: f != null) (map processFile allFiles);

        # Separate config files from plugin files
        configFilesList = lib.filter (f:
          lib.elem f.category ["keymaps" "options" "autocmds"]
        ) processedFiles;

        pluginFilesList = lib.filter (f:
          lib.hasPrefix "plugin:" f.category
        ) processedFiles;

        # Convert to attribute sets for easier access
        configFiles = lib.listToAttrs (map (f:
          lib.nameValuePair f.category f
        ) configFilesList);

        pluginFiles = lib.listToAttrs (map (f:
          let
            pluginName = lib.removePrefix "plugin:" f.category;
          in
            lib.nameValuePair pluginName f
        ) pluginFilesList);
      in
        { inherit configFiles pluginFiles; };

  # Scan config files if provided
  scannedFiles = scanConfigFiles cfg.configFiles;

  # Detect conflicts between configFiles and existing options
  conflictChecks =
    let
      # Check config file conflicts
      keymapsConflict = scannedFiles.configFiles ? keymaps && cfg.config.keymaps != "";
      optionsConflict = scannedFiles.configFiles ? options && cfg.config.options != "";
      autocmdsConflict = scannedFiles.configFiles ? autocmds && cfg.config.autocmds != "";

      # Check plugin file conflicts
      pluginConflicts = lib.intersectLists
        (lib.attrNames scannedFiles.pluginFiles)
        (lib.attrNames cfg.plugins);

      # Build error messages
      errorMessages = []
        ++ lib.optional keymapsConflict ''
          Conflict: Both configFiles provides 'lua/config/keymaps.lua' and config.keymaps is set.
          Please use only one method to configure keymaps:
          - Either remove config.keymaps from your configuration
          - Or remove lua/config/keymaps.lua from your configFiles directory''
        ++ lib.optional optionsConflict ''
          Conflict: Both configFiles provides 'lua/config/options.lua' and config.options is set.
          Please use only one method to configure options:
          - Either remove config.options from your configuration
          - Or remove lua/config/options.lua from your configFiles directory''
        ++ lib.optional autocmdsConflict ''
          Conflict: Both configFiles provides 'lua/config/autocmds.lua' and config.autocmds is set.
          Please use only one method to configure autocmds:
          - Either remove config.autocmds from your configuration
          - Or remove lua/config/autocmds.lua from your configFiles directory''
        ++ lib.optionals (pluginConflicts != []) [''
          Conflict: Plugin file(s) ${lib.concatStringsSep ", " (map (p: "'${p}.lua'") pluginConflicts)} exist in both configFiles and plugins option.
          Please use only one method to configure these plugins:
          - Either remove the corresponding entries from your plugins configuration
          - Or remove the lua files from your configFiles directory''];
    in
      if errorMessages != [] then
        builtins.throw (lib.concatStringsSep "\n\n" errorMessages)
      else
        null;

  # Ensure no conflicts exist (this will throw if there are conflicts)
  _ = if cfg.enable then conflictChecks else null;

in {
  options.programs.lazyvim = {
    enable = mkEnableOption "LazyVim - A Neovim configuration framework";

    pluginSource = mkOption {
      type = types.enum [ "latest" "nixpkgs" ];
      default = "latest";
      description = ''
        Plugin source strategy:
        - "latest": Use nixpkgs if it has the required version, otherwise build from source
        - "nixpkgs": Prefer nixpkgs versions, fallback to source if unavailable
      '';
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      example = literalExpression ''
        with pkgs; [
          rust-analyzer
          gopls
          nodePackages.typescript-language-server
        ]
      '';
      description = ''
        Additional packages to be made available to LazyVim.
        This should include LSP servers, formatters, linters, and other tools.
      '';
    };
    
    treesitterParsers = mkOption {
      type = types.listOf types.package;
      default = [];
      example = literalExpression ''
        with pkgs.tree-sitter-grammars; [
          # Minimal for LazyVim itself
          tree-sitter-lua
          tree-sitter-vim
          tree-sitter-query
          
          # Common languages
          tree-sitter-rust
          tree-sitter-go
          tree-sitter-typescript
          tree-sitter-tsx
          tree-sitter-python
        ]
      '';
      description = ''
        List of Treesitter parser packages to install.
        
        Empty by default - add parsers based on languages you use.
        These should be packages from pkgs.tree-sitter-grammars.
        
        NOTE: Parser compatibility issues may occur if there's a version mismatch
        between nvim-treesitter and the parsers. If you see "Invalid node type" 
        errors, try using a matching nixpkgs channel or pinning versions.
      '';
    };

    configFiles = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = literalExpression ''
        ./lazyvim-config
      '';
      description = ''
        Path to a directory containing LazyVim configuration files.
        The directory structure should follow this convention:

        - config/keymaps.lua - Custom keymaps
        - config/options.lua - Vim options
        - config/autocmds.lua - Auto commands
        - plugins/*.lua - Plugin configurations

        Files from this directory will be copied to the appropriate locations
        in ~/.config/nvim/lua/. If you also specify individual config options
        (config.keymaps, config.options, etc.) or plugins, conflicts will
        cause the build to fail with a descriptive error message.
      '';
    };

    config = mkOption {
      type = types.submodule {
        options = {
          autocmds = mkOption {
            type = types.str;
            default = "";
            example = ''
              -- Auto-save on focus loss
              vim.api.nvim_create_autocmd("FocusLost", {
                command = "silent! wa",
              })
            '';
            description = ''
              Lua code for autocmds that will be written to lua/config/autocmds.lua.
              This file is loaded by LazyVim for user autocmd configurations.
            '';
          };
          
          keymaps = mkOption {
            type = types.str;
            default = "";
            example = ''
              -- Custom keymaps
              vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", { desc = "Save file" })
              vim.keymap.set("n", "<C-h>", "<cmd>TmuxNavigateLeft<cr>", { desc = "Go to left window" })
            '';
            description = ''
              Lua code for keymaps that will be written to lua/config/keymaps.lua.
              This file is loaded by LazyVim for user keymap configurations.
            '';
          };
          
          options = mkOption {
            type = types.str;
            default = "";
            example = ''
              -- Custom vim options
              vim.opt.relativenumber = false
              vim.opt.wrap = true
              vim.opt.conceallevel = 0
            '';
            description = ''
              Lua code for vim options that will be written to lua/config/options.lua.
              This file is loaded by LazyVim for user option configurations.
            '';
          };
        };
      };
      default = {};
      description = ''
        LazyVim configuration files. These map to the lua/config/ directory structure
        and are loaded by LazyVim automatically.
      '';
    };
    
    extras = mkOption {
      type = types.attrsOf (types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "this LazyVim extra";

          config = mkOption {
            type = types.str;
            default = "";
            description = ''
              Complete Lua plugin specification to override or extend this extra.
              Should contain a complete lazy.nvim plugin spec with return statement.
            '';
          };
        };
      }));
      default = {};
      example = literalExpression ''
        {
          coding.yanky = {
            enable = true;
            config = '''
              return {
                "gbprod/yanky.nvim",
                opts = {
                  highlight = { timer = 300 },
                },
              }
            ''';
          };

          lang.nix = {
            enable = true;
            config = '''
              return {
                "neovim/nvim-lspconfig",
                opts = {
                  servers = {
                    nixd = {},
                  },
                },
              }
            ''';
          };

          editor.dial.enable = true;
        }
      '';
      description = ''
        LazyVim extras to enable. Extras provide additional plugins and configurations
        for specific languages, features, or tools.

        Each extra can be enabled with `enable = true` and optionally configured with
        complete lazy.nvim plugin specifications in the `config` field.
      '';
    };

    plugins = mkOption {
      type = types.attrsOf types.str;
      default = {};
      example = literalExpression ''
        {
          custom-theme = '''
            return {
              "folke/tokyonight.nvim",
              opts = {
                style = "night",
                transparent = true,
              },
            }
          ''';

          lsp-config = '''
            return {
              "neovim/nvim-lspconfig",
              opts = function(_, opts)
                opts.servers.rust_analyzer = {
                  settings = {
                    ["rust-analyzer"] = {
                      checkOnSave = {
                        command = "clippy",
                      },
                    },
                  },
                }
              end,
            }
          ''';
        }
      '';
      description = ''
        Plugin configuration files. Each key becomes a file lua/plugins/{key}.lua
        with the corresponding Lua code. These files are automatically loaded by LazyVim.
      '';
    };
  };
  
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
      extraPackages = cfg.extraPackages ++ (with pkgs; [
        # Required by LazyVim
        git
        ripgrep
        fd
        
        # Language servers and tools can be added by the user
      ]);
      
      # Add lazy.nvim as a plugin
      plugins = [ pkgs.vimPlugins.lazy-nvim ];
    };
    
    # Create LazyVim configuration
    xdg.configFile = {
      "nvim/init.lua".text = lazyConfig;
      
      # Link treesitter parsers only if parsers are configured
      "nvim/parser" = mkIf (automaticTreesitterParsers != []) {
        source = "${treesitterGrammars}/parser";
      };
      
      # LazyVim config files - use configFiles if available, otherwise use string options
      "nvim/lua/config/autocmds.lua" = mkIf (
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

      "nvim/lua/config/keymaps.lua" = mkIf (
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

      "nvim/lua/config/options.lua" = mkIf (
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
      lib.nameValuePair "nvim/lua/plugins/${name}.lua" {
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
    // extrasConfigFiles;
  };
}
