# Dev path creation utilities for LazyVim Nix module
{ lib, pkgs, pluginMappings }:

rec {
  # Helper function to create dev path with proper symlinks for all plugins
  createDevPath = allPluginSpecs: allResolvedPlugins:
    let
      # Separate multi-module plugins from regular plugins
      pluginWithType = lib.zipListsWith (spec: plugin:
        if plugin != null then
          let
            mapping = pluginMappings.${spec.name} or null;
            isMultiModule = mapping != null && builtins.isAttrs mapping && mapping ? module;
          in {
            inherit spec;
            inherit plugin;
            inherit isMultiModule;
            linkName = if isMultiModule then mapping.module else getRepoName spec.name;
          }
        else null
      ) allPluginSpecs allResolvedPlugins;

      # Filter out null entries
      validPlugins = lib.filter (p: p != null) pluginWithType;

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

  # Extract repository name from plugin spec (needed for config generation)
  getRepoName = specName:
    let parts = lib.splitString "/" specName;
    in if lib.length parts == 2 then lib.elemAt parts 1 else specName;

  # Generate dev plugin specs for available plugins
  generateDevPluginSpecs = self: allPluginSpecs: resolvedPlugins:
    let
      devPluginSpecs = lib.zipListsWith (spec: plugin:
        if plugin != null &&
           spec.name != "nvim-treesitter/nvim-treesitter" &&
           spec.name != "nvim-treesitter/nvim-treesitter-textobjects" then
          ''{ "${self.getRepoName spec.name}", dev = true, pin = true },''
        else
          null
      ) allPluginSpecs resolvedPlugins;

      # Filter out null entries
      availableDevSpecs = lib.filter (s: s != null) devPluginSpecs;
    in
      availableDevSpecs;
}
