# Run with nix-instantiate --eval --strict --expr 'import ./scripts/check-parser-manifest.nix {}'.
{ pkgs ? (builtins.getFlake (toString ../.)).inputs.nixpkgs.legacyPackages.${builtins.currentSystem} }:
let
  data = import ../nix/lib/data-loading.nix { inherit pkgs; inherit (pkgs) lib; };
  resolver = import ../nix/lib/plugin-resolution.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    inherit (data) pluginMappings;
    ignoreBuildNotifications = true;
  };
  spec = pkgs.lib.findFirst (p: p.name == "nvim-treesitter/nvim-treesitter")
    (throw "Missing nvim-treesitter plugin in data/plugins.json") data.pluginData.plugins;
  check = import ../nix/lib/parser-coherence.nix {
    manifest = builtins.fromJSON (builtins.readFile ../data/parser-manifest.json);
    plugin = resolver.resolvePlugin { pluginSource = "latest"; } spec;
  };
in
  if check.assertion then true else throw check.message
