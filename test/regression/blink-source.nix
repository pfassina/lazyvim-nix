{ pkgs, ... }:
let
  inherit (pkgs) lib;
  # Force the consumer's nixpkgs version to differ, exercising the source path.
  consumerPkgs = pkgs // { vimPlugins = pkgs.vimPlugins // {
    blink-cmp = pkgs.vimPlugins.blink-cmp // { src.rev = "different-nixpkgs-revision"; };
  }; };
  resolver = import ../../nix/lib/plugin-resolution.nix {
    inherit lib;
    pkgs = consumerPkgs;
    pluginMappings = { "saghen/blink.cmp" = "blink-cmp"; };
    ignoreBuildNotifications = true;
  };
  spec = lib.findFirst (p: p.name == "saghen/blink.cmp") null
    (builtins.fromJSON (builtins.readFile ../../data/plugins.json)).plugins;
  blink = resolver.resolvePlugin { pluginSource = "latest"; } spec;
  check = pkgs.writeText "blink-source-check.lua" ''
    vim.opt.runtimepath:prepend("${blink}")
    require("blink.cmp").setup({ fuzzy = { implementation = "rust" } })
    assert(vim.wait(5000, function()
      return require("blink.cmp.fuzzy").implementation_type == "rust"
    end), "source-built Blink did not initialize its native matcher")
    local words = require("blink.cmp.fuzzy").get_words("hello world")
    assert(vim.tbl_contains(words, "hello") and vim.tbl_contains(words, "world"), vim.inspect(words))
    print("Source-built Blink initializes and matches with Rust offline")
  '';
in {
  test-blink-source-native-matcher = pkgs.runCommand "test-blink-source-native-matcher" {
    nativeBuildInputs = [ pkgs.neovim-unwrapped ];
  } ''
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
    export XDG_STATE_HOME="$HOME/state" XDG_CACHE_HOME="$HOME/cache"
    mkdir -p "$HOME"
    nvim --headless -u NONE -l ${check}
    touch "$out"
  '';
}
