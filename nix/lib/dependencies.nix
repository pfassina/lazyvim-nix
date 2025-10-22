# System dependencies management for LazyVim Nix module
{ lib, pkgs, dependencies }:

{
  # Calculate system dependencies based on enabled features
  systemPackages = cfg:
    if cfg.enable then
      let
        # Get enabled extra names in "category.name" format for lookup
        enabledExtraNames = lib.flatten (lib.mapAttrsToList (category: extras:
          lib.mapAttrsToList (name: extraConfig:
            lib.optional (extraConfig.enable or false) "${category}.${name}"
          ) extras
        ) (cfg.extras or {}));

        # Helper function to resolve a package name to nixpkgs package
        resolvePackage = pkgName:
          if pkgs ? ${pkgName} then pkgs.${pkgName}
          else builtins.trace "Warning: Package '${pkgName}' not found in nixpkgs" null;

        # Helper function to warn about unmapped tools
        warnUnmappedTool = toolName: extraName:
          builtins.trace ''
            Warning: Tool '${toolName}' in extra '${extraName}' has no nixpkgs mapping.

            This tool will be skipped during installation. To resolve this:
            1. Manually install the tool via extraPackages, or
            2. Consider contributing a nixpkgs mapping at:
               https://github.com/user/lazyvim-nix/issues

            Include the tool name '${toolName}' and suggest a nixpkgs package name.
          '' null;

        # Get core packages (only if installCoreDependencies is enabled)
        corePackages = if cfg.installCoreDependencies then
          lib.filter (pkg: pkg != null) (map (tool:
            if tool ? nixpkg then resolvePackage tool.nixpkg else null
          ) (dependencies.core or []))
        else [];

        # Get packages for enabled extras based on installation options
        extraPackages = lib.flatten (map (extraName:
          let
            # Split "category.name" into parts to access cfg.extras
            parts = lib.splitString "." extraName;
            category = lib.head parts;
            name = lib.last parts;
            extraConfig = cfg.extras.${category}.${name} or {};
            extraTools = dependencies.extras.${extraName} or [];

            # Check installation options
            shouldInstallDependencies = extraConfig.installDependencies or false;
            shouldInstallRuntimeDependencies = extraConfig.installRuntimeDependencies or false;
          in
            if extraTools != [] then
              let
                # Get tool packages (only if installDependencies is enabled)
                toolPackages = if shouldInstallDependencies then
                  lib.filter (pkg: pkg != null) (map (tool:
                    if tool ? nixpkg then
                      resolvePackage tool.nixpkg
                    else
                      warnUnmappedTool tool.name extraName
                  ) extraTools)
                else [];

                # Get runtime dependency packages (only if installRuntimeDependencies is enabled)
                runtimeDependencyPackages = if shouldInstallRuntimeDependencies then
                  lib.unique (lib.flatten (map (tool:
                    if tool ? runtime_dependencies then map (dep:
                      if dep ? nixpkg then
                        resolvePackage dep.nixpkg
                      else
                        builtins.trace "Info: Runtime dependency '${dep.name}' for tool '${tool.name}' in '${extraName}' has no nixpkg mapping (may be a package manager like pip/npm)" null
                    ) tool.runtime_dependencies else []
                  ) extraTools))
                else [];

                # Filter out nulls from runtime dependency packages
                validRuntimeDependencyPackages = lib.filter (pkg: pkg != null) runtimeDependencyPackages;
              in
                toolPackages ++ validRuntimeDependencyPackages
            else []
        ) enabledExtraNames);

        # Combine and deduplicate all packages
        allPackages = lib.unique (corePackages ++ extraPackages);
      in
        allPackages
    else
      [];
}