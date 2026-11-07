# Evaluate LazyVim's own default selection, including executable user options.
{ lib, pkgs }:
{
  resolve = { neovim, lazyvim, optionsFile, explicitExtras, configPath ? null }:
    let
      imports = map (name: { import = "lazyvim.plugins.extras.${name}"; }) explicitExtras;
      input = pkgs.writeText "lazyvim-default-extras-input.json" (builtins.toJSON {
        inherit imports;
        config = if configPath == null then null else toString configPath;
      });
      result = pkgs.runCommand "lazyvim-default-extras.json" { } ''
        export HOME="$TMPDIR"
        export XDG_CONFIG_HOME="$TMPDIR/config"
        export XDG_DATA_HOME="$TMPDIR/data"
        export XDG_STATE_HOME="$TMPDIR/state"
        export XDG_CACHE_HOME="$TMPDIR/cache"
        mkdir -p "$XDG_CONFIG_HOME/nvim/lua/config"
        cp ${optionsFile} "$XDG_CONFIG_HOME/nvim/lua/config/options.lua"
        ${neovim}/bin/nvim --headless -u NONE -l ${./default-extras.lua} \
          ${lazyvim} ${pkgs.vimPlugins.lazy-nvim} ${input} "$out"
      '';
    in builtins.fromJSON (builtins.readFile result);
}
