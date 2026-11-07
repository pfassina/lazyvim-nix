# Validate with the same Neovim package that will load these parsers at runtime.
{ pkgs }:
{ neovim, parsers, queries }:
pkgs.runCommand "treesitter-queries-validated" { } ''
  export HOME="$TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/config"
  export XDG_DATA_HOME="$HOME/data"
  export XDG_STATE_HOME="$HOME/state"
  export XDG_CACHE_HOME="$HOME/cache"
  mkdir -p "$HOME" site
  ln -s ${parsers}/parser site/parser
  ln -s ${queries} site/queries
  export LAZYVIM_TREESITTER_SITE="$PWD/site"
  ${neovim}/bin/nvim --headless -u NONE -i NONE -n -l ${./validate-treesitter.lua}
  ln -s ${queries} "$out"
''
