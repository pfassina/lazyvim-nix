{
  pkgs,
  testLib,
  ...
}:
let
  packagePathsLib = import ../../nix/lib/package-paths.nix { inherit (pkgs) lib; };
  typescriptSveltePlugin = "/nix/store/typescript-svelte-plugin";
  target = "lazyvim/lua/plugins/_lazyvim_nix_package_paths.lua";

  enabledConfigFiles = packagePathsLib.configFiles {
    appName = "lazyvim";
    enabledExtraNames = [ "lang.svelte" ];
    inherit typescriptSveltePlugin;
  };

  disabledConfigFiles = packagePathsLib.configFiles {
    appName = "lazyvim";
    enabledExtraNames = [ ];
    inherit typescriptSveltePlugin;
  };

  config = enabledConfigFiles.${target}.text;
in
{
  test-package-path-config-enabled = testLib.testEval "package-path-config-enabled" (
    enabledConfigFiles ? ${target}
  ) true;

  test-package-path-config-uses-lazyvim-resolver =
    testLib.testEval "package-path-config-uses-lazyvim-resolver"
      (pkgs.lib.hasInfix "package_path = function(pkg, path)" config)
      true;

  test-package-path-config-source = testLib.testEval "package-path-config-source" (
    pkgs.lib.hasInfix ''["svelte-language-server/node_modules/typescript-svelte-plugin"] ='' config
    && pkgs.lib.hasInfix ''"/nix/store/typescript-svelte-plugin/lib/node_modules/typescript-svelte-plugin"'' config
  ) true;

  test-package-path-config-disabled = testLib.testEval "package-path-config-disabled" (
    disabledConfigFiles == { }
  ) true;
}
