# File scanning and conflict detection utilities for LazyVim Nix module
{ lib }:

{
  scanUserPlugins = config_path:
    let
      pluginsDir = config_path + "/lua/plugins";
    in
      if !builtins.pathExists pluginsDir then []
      else let
        luaFiles = lib.filter
          (p: lib.hasSuffix ".lua" (toString p))
          (lib.filesystem.listFilesRecursive pluginsDir);

        tokenRe = ''"([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)"'';

        extractFromFile = p:
          let
            content = builtins.readFile p;
            matches = builtins.filter builtins.isList
              (builtins.split tokenRe content);
            names = lib.unique (map (m: builtins.head m) matches);
          in map (name:
            let parts = lib.splitString "/" name; in {
              inherit name;
              owner = builtins.elemAt parts 0;
              repo  = builtins.elemAt parts 1;
              source_file = baseNameOf (toString p);
              user_plugin = true;
            }
          ) names;

        all = lib.concatMap extractFromFile luaFiles;
        dedup = lib.foldl' (acc: p:
          if lib.any (q: q.name == p.name) acc then acc else acc ++ [p]
        ) [] all;
      in lib.sort (a: b: a.name < b.name) dedup;

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
      errorMessages = lib.optional keymapsConflict ''
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
