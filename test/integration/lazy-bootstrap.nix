# Exercise the generated bootstrap against a real Nix-provided start package.
{ pkgs, ... }:
let
  inherit (pkgs) lib;
  configLib = import ../../nix/lib/config-generation.nix { inherit lib; };
  dataLib = import ../../nix/lib/data-loading.nix { inherit lib pkgs; };
  patchedConfig = configLib.lazyConfig {
    inherit (dataLib) starterLua starterVersion;
    devPath = "/unused";
    extrasImportSpecs = [ ];
    availableDevSpecs = [ ];
  };
  # Isolate bootstrap startup from the unrelated LazyVim plugin configuration.
  bootstrap = lib.head (lib.splitString ''require("lazy").setup('' patchedConfig);
  init = pkgs.writeText "lazy-bootstrap-init.lua" ''
    ${bootstrap}
    local lazy = require("lazy")
    local source = debug.getinfo(lazy.setup, "S").source
    print("lazy setup source: " .. source)
    assert(source:find("/site/pack/hm/start/lazy.nvim/", 1, true), source)
    lazy.setup({ spec = {}, install = { missing = false }, checker = { enabled = false } })
    local cloned = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
    assert(not vim.uv.fs_stat(cloned), "lazy.nvim was cloned: " .. cloned)
  '';
in {
  test-lazy-bootstrap-start-package = pkgs.runCommand "test-lazy-bootstrap-start-package" {
    nativeBuildInputs = [ pkgs.neovim-unwrapped ];
  } ''
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_DATA_HOME="$HOME/.local/share"
    export XDG_STATE_HOME="$HOME/.local/state"
    export XDG_CACHE_HOME="$HOME/.cache"
    mkdir -p "$XDG_DATA_HOME/nvim/site/pack/hm/start"
    ln -s ${pkgs.vimPlugins.lazy-nvim} "$XDG_DATA_HOME/nvim/site/pack/hm/start/lazy.nvim"
    nvim --headless -u ${init} \
      -c 'if v:errmsg != "" | cquit | endif' -c 'qa!'
    test ! -e "$XDG_DATA_HOME/nvim/lazy/lazy.nvim"
    touch "$out"
  '';
}