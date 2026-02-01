# Plugin resolution and building utilities for LazyVim Nix module
{ lib, pkgs, pluginMappings, ignoreBuildNotifications ? false }:

let
  self = {
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

      # SHA256 hash is required for fetchgit
      sha256 = versionInfo.sha256 or null;

      # For latest/HEAD, use fetchGit which doesn't require a hash
      # For pinned versions with sha256, use fetchgit (content-addressed, immune to GitHub tarball regeneration)
      src = if rev == "HEAD" || sha256 == null then
        builtins.fetchGit ({
          url = "https://github.com/${owner}/${repo}";
          shallow = true;
        } // lib.optionalAttrs (rev != "HEAD") {
          ref = rev;
        })
      else
        pkgs.fetchgit {
          url = "https://github.com/${owner}/${repo}";
          inherit rev sha256;
          fetchSubmodules = false;
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
          repoName = if lib.length parts == 2 then lib.elemAt parts 1 else lazyName;

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

  # Enhanced plugin resolver with version-aware strategy
  resolvePlugin = cfg: pluginSpec:
    let
      nixName = self.resolvePluginName pluginSpec.name;
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
        self.buildVimPluginFromSource pluginSpec
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
        if ignoreBuildNotifications then (x: x)
        else if builtins.elem pluginSpec.name ["LazyVim/LazyVim" "folke/lazy.nvim"] then
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
          if ignoreBuildNotifications then null
          else builtins.trace "Warning: Could not resolve plugin ${pluginSpec.name}" null
        else
          finalPlugin
      );
  };
in
  self