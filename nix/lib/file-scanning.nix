# File scanning and conflict detection utilities for LazyVim Nix module
{ lib, pkgs, config }:

{
  # Function to scan user plugins from LazyVim configuration
  scanUserPlugins = config_path:
    let
      # Use Nix to call the Lua scanner script
      scanResult = pkgs.runCommand "scan-user-plugins" {
        buildInputs = [ pkgs.lua pkgs.neovim pkgs.luaPackages.luv ];
      } ''
        # Copy scanner script to build directory
        cp ${../../scripts/scan-user-plugins.lua} scan-user-plugins.lua

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

  # Helper function to scan config files from a directory
  scanConfigFiles = configPath: appName:
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
                "${appName}/${relPath}"
              else if lib.hasPrefix "config/" relPath then
                # config/ at root, add lua/ prefix
                "${appName}/lua/${relPath}"
              else if lib.hasPrefix "plugins/" relPath then
                # plugins/ at root, add lua/ prefix
                "${appName}/lua/${relPath}"
              else
                # Other structure - put under lua/
                "${appName}/lua/${relPath}";

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

  # Detect conflicts between configFiles and existing options
  detectConflicts = cfg: scannedFiles:
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
}
