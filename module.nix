{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.lazyvim;

  # Load plugin data and mappings
  pluginData = pkgs.lazyvimPluginData or (builtins.fromJSON (builtins.readFile ./plugins.json));
  pluginMappings = pkgs.lazyvimPluginMappings or (import ./plugin-mappings.nix);
  pluginOverrides = pkgs.lazyvimOverrides or (import ./overrides/default.nix { inherit pkgs; });

  # Helper function to build a vim plugin from source
  buildVimPluginFromSource = pluginSpec:
    let
      owner = pluginSpec.owner or (builtins.elemAt (lib.splitString "/" pluginSpec.name) 0);
      repo = pluginSpec.repo or (builtins.elemAt (lib.splitString "/" pluginSpec.name) 1);
      versionInfo = pluginSpec.version_info or {};

      # Use tag if available, otherwise commit, otherwise HEAD
      rev = if versionInfo.tag != null then versionInfo.tag
            else if versionInfo.commit != null then versionInfo.commit
            else "HEAD";

      # SHA256 hash is required for deterministic builds
      sha256 = versionInfo.sha256 or lib.fakeSha256;
    in
      if owner != null && repo != null then
        pkgs.vimUtils.buildVimPlugin {
          pname = repo;
          version = rev;
          src = pkgs.fetchFromGitHub {
            inherit owner repo rev sha256;
          };
          doCheck = false;  # Disable require checks that may fail
          meta = {
            description = "LazyVim plugin: ${pluginSpec.name}";
            homepage = "https://github.com/${owner}/${repo}";
          };
        }
      else
        null;

  # Function to check if nixpkgs plugin version matches required version
  checkPluginVersion = pluginSpec: nixPlugin:
    let
      versionInfo = pluginSpec.version_info or {};
      requiredCommit = versionInfo.commit or null;
      requiredTag = versionInfo.tag or null;
    in
      # For now, we'll be conservative and only use nixpkgs if we don't have version info
      # or if explicitly enabled. This can be enhanced later with actual version checking
      if cfg.preferNixpkgs or (requiredCommit == null && requiredTag == null) then
        true
      else
        false;
  
  # Helper function to resolve plugin names
  resolvePluginName = lazyName:
    let
      mapping = pluginMappings.${lazyName} or null;
    in
      if mapping == null then
        # Try automatic resolution
        let
          parts = lib.splitString "/" lazyName;
          repoName = if length parts == 2 then elemAt parts 1 else lazyName;
          # Convert repo-name to repo_name and repo.nvim to repo-nvim
          nixName = lib.replaceStrings ["-" "."] ["_" "-"] repoName;
        in nixName
      else if builtins.isString mapping then
        mapping
      else
        mapping.package;
  
  # Helper function to detect multi-module plugins
  detectMultiModulePlugins = pluginSpecs:
    let
      isMultiModulePlugin = pluginSpec:
        let
          mapping = pluginMappings.${pluginSpec.name} or null;
        in
          mapping != null && builtins.isAttrs mapping && mapping ? module;
    in
      filter isMultiModulePlugin pluginSpecs;
  
  # Helper function to expand multi-module plugins into individual entries
  expandMultiModulePlugins = pluginSpecs:
    let
      multiModulePlugins = detectMultiModulePlugins pluginSpecs;
      regularPlugins = filter (spec: 
        let
          mapping = pluginMappings.${spec.name} or null;
        in
          mapping == null || builtins.isString mapping || !(mapping ? module)
      ) pluginSpecs;
      
      # Create individual entries for multi-module plugins
      expandedEntries = map (pluginSpec:
        let
          mapping = pluginMappings.${pluginSpec.name};
          nixName = resolvePluginName pluginSpec.name;
          plugin = pkgs.vimPlugins.${nixName} or null;
        in
          if plugin == null then
            null
          else
            {
              name = mapping.module;  # Use module name for LazyVim to find
              nixName = nixName;
              plugin = plugin;
              originalSpec = pluginSpec;
            }
      ) multiModulePlugins;
    in
      {
        regular = regularPlugins;
        expanded = filter (entry: entry != null) expandedEntries;
      };

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
        cp ${./scripts/scan-user-plugins.lua} scan-user-plugins.lua

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

  # Merge core plugins with user plugins
  corePlugins = pluginData.plugins or [];
  allPluginSpecs = corePlugins ++ userPlugins;

  # Expand multi-module plugins and separate regular plugins
  pluginSeparation = expandMultiModulePlugins allPluginSpecs;

  # Smart plugin resolver that chooses between nixpkgs and source builds
  resolvePlugin = pluginSpec:
    let
      nixName = resolvePluginName pluginSpec.name;
      nixPlugin = pkgs.vimPlugins.${nixName} or null;
      versionInfo = pluginSpec.version_info or {};
      hasVersionInfo = versionInfo ? sha256 && versionInfo.sha256 != null && versionInfo.sha256 != "";

      # Decision logic for plugin source
      useNixpkgs =
        # Use nixpkgs if user explicitly prefers it
        cfg.preferNixpkgs ||
        # Use nixpkgs if we don't have version info
        (!hasVersionInfo) ||
        # Use nixpkgs if alwaysLatest is disabled and plugin exists in nixpkgs
        (!cfg.alwaysLatest && nixPlugin != null) ||
        # Use nixpkgs if plugin not available and we can't build from source
        (nixPlugin == null && !hasVersionInfo);

      # Build from source if needed
      sourcePlugin = if hasVersionInfo then buildVimPluginFromSource pluginSpec else null;

      # Final plugin selection
      finalPlugin =
        if useNixpkgs && nixPlugin != null then
          nixPlugin
        else if sourcePlugin != null then
          sourcePlugin
        else if nixPlugin != null then
          nixPlugin  # Fallback to nixpkgs even if outdated
        else
          null;

      # Debug trace for important plugins
      debugTrace =
        if pluginSpec.name == "LazyVim/LazyVim" && finalPlugin != null then
          builtins.trace "LazyVim: Using ${if useNixpkgs then "nixpkgs" else "source build"} version"
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
    if plugin != null then
      ''{ "${getRepoName spec.name}", dev = true },''
    else
      null
  ) allPluginSpecs resolvedPlugins;
  
  # Filter out null entries
  availableDevSpecs = filter (s: s != null) devPluginSpecs;
  
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
      dev = {
        path = "${devPath}",
        patterns = {},  -- Don't automatically match, use explicit dev = true
        fallback = false,
      },
      spec = {
        { "LazyVim/LazyVim", import = "lazyvim.plugins", dev = true },
        -- Disable Mason.nvim in Nix environment
        { "mason-org/mason.nvim", enabled = false },
        { "mason-org/mason-lspconfig.nvim", enabled = false },
        { "jay-babu/mason-nvim-dap.nvim", enabled = false },
        -- Disable treesitter auto-install - simple approach like your old config
        { 
          "nvim-treesitter/nvim-treesitter", 
          opts = function(_, opts)
            opts.ensure_installed = {}
          end,
          dev = true,
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
  
  # Treesitter configuration - using packages directly
  treesitterGrammars = let
    parsers = pkgs.symlinkJoin {
      name = "treesitter-parsers";
      paths = (pkgs.vimPlugins.nvim-treesitter.withPlugins (_: cfg.treesitterParsers)).dependencies;
    };
  in parsers;

in {
  options.programs.lazyvim = {
    enable = mkEnableOption "LazyVim - A Neovim configuration framework";

    preferNixpkgs = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to prefer nixpkgs versions of plugins over building from source.
        When false (default), the flake will build plugins from source when version
        information is available to ensure you get the exact versions specified.
        When true, nixpkgs versions are used whenever possible for faster builds.
      '';
    };

    alwaysLatest = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to always use the latest plugin versions by building from source.
        When true (default), plugins with version info will be built from source.
        When false, nixpkgs versions are preferred unless unavailable.
        This option is ignored if preferNixpkgs is true.
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
      "nvim/parser" = mkIf (cfg.treesitterParsers != []) {
        source = "${treesitterGrammars}/parser";
      };
      
      # LazyVim config files
      "nvim/lua/config/autocmds.lua" = mkIf (cfg.config.autocmds != "") {
        text = ''
          -- User autocmds configured via Nix
          ${cfg.config.autocmds}
        '';
      };
      
      "nvim/lua/config/keymaps.lua" = mkIf (cfg.config.keymaps != "") {
        text = ''
          -- User keymaps configured via Nix
          ${cfg.config.keymaps}
        '';
      };
      
      "nvim/lua/config/options.lua" = mkIf (cfg.config.options != "") {
        text = ''
          -- User options configured via Nix
          ${cfg.config.options}
        '';
      };
      
    } 
    # Generate plugin configuration files
    // (lib.mapAttrs' (name: content: 
      lib.nameValuePair "nvim/lua/plugins/${name}.lua" {
        text = ''
          -- Plugin configuration for ${name} (configured via Nix)
          ${content}
        '';
      }
    ) cfg.plugins);
  };
}
