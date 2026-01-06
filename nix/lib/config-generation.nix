# Configuration generation utilities for LazyVim Nix module
{ lib }:

let
  starterPatcher = import ./starter-patcher.nix { inherit lib; };
in
{
  # Generate extras import statements
  extrasImportSpecs = enabledExtras:
    map (extra: ''{ import = "${extra.import}" },'') enabledExtras;

  # Generate extras config override files for extras with custom config
  extrasConfigFiles = enabledExtras: appName:
    let
      extrasWithConfig = lib.filter (extra: extra.hasConfig) enabledExtras;
    in
      lib.listToAttrs (map (extra:
        lib.nameValuePair
          "${appName}/lua/plugins/extras-${extra.category}-${extra.name}.lua"
          {
            text = ''
              -- Extra configuration override for ${extra.category}/${extra.name} (configured via Nix)
              -- This file overrides the default configuration from the LazyVim extra
              ${extra.config}
            '';
          }
      ) extrasWithConfig);

  # Generate lazy.nvim configuration by patching the official LazyVim starter
  # This approach preserves upstream improvements while injecting Nix-specific overrides
  lazyConfig = {
    starterLua,
    starterVersion,
    devPath,
    extrasImportSpecs,
    availableDevSpecs
  }:
    starterPatcher.patchStarterConfig {
      inherit starterLua starterVersion devPath extrasImportSpecs availableDevSpecs;
      treesitterSpec = starterPatcher.defaultTreesitterSpec;
    };
}
