# Compare the selected plugin source, not version_info.commit: versions/tags and
# nixpkgs fallbacks can select a different revision in resolvePlugin.
{ manifest, plugin }:
let
  revision = if plugin == null then null else plugin.src.rev or null;
  commit = manifest.nvim_treesitter_commit or null;
in {
  assertion = commit != null && revision != null && commit == revision;
  message = ''
    lazyvim-nix parser manifest does not match the resolved nvim-treesitter source
    (manifest: ${if commit == null then "missing" else commit}, resolved: ${if revision == null then "missing" else revision}).
    Run scripts/update-plugins.sh to regenerate data/parser-manifest.json for the
    selected plugin revision, or use programs.lazyvim.pluginSource = "nixpkgs".
  '';
}
