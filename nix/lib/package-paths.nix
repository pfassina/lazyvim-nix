# Package path resolution for LazyVim extras under Nix
{ lib }: {
  configFiles =
    {
      appName,
      enabledExtraNames,
      typescriptSveltePlugin,
    }:
    lib.optionalAttrs (lib.elem "lang.svelte" enabledExtraNames) {
      "${appName}/lua/plugins/_lazyvim_nix_package_paths.lua" = {
        text = ''
          -- [NIX] Resolve packages provided by Nix instead of Mason.
          local package_paths = {
            ["svelte-language-server/node_modules/typescript-svelte-plugin"] =
              "${typescriptSveltePlugin}/lib/node_modules/typescript-svelte-plugin",
          }

          return {
            {
              "LazyVim/LazyVim",
              opts = {
                package_path = function(pkg, path)
                  return package_paths[pkg .. path]
                end,
              },
            },
          }
        '';
      };
    };
}
