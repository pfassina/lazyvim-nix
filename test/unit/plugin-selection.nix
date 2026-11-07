{ pkgs, testLib, ... }:
let
  inherit (pkgs) lib;
  selection = import ../../nix/lib/plugin-selection.nix { inherit lib; };
  resolver = import ../../nix/lib/plugin-resolution.nix {
    inherit lib pkgs;
    pluginMappings = { "saghen/blink.compat" = "blink-compat"; };
    ignoreBuildNotifications = true;
  };
  selected = selection.withDependencies [
    { name = "owner/parent"; dependencies = [ "owner/child" "rafamadriz/friendly-snippets" ]; }
    { name = "owner/child"; dependencies = [ "owner/parent" "rafamadriz/friendly-snippets" ]; }
  ] [ { name = "owner/parent"; dependencies = [ "owner/child" "rafamadriz/friendly-snippets" ]; } ];
  names = map (p: p.name) selected;
in {
  test-plugin-dependency-closure = testLib.testEval "plugin-dependency-closure"
    (names == [ "owner/parent" "owner/child" "rafamadriz/friendly-snippets" ]) true;
  test-dependency-repository-fallback = testLib.testEval "dependency-repository-fallback"
    ((resolver.resolveDependency { pluginSource = "latest"; } {
      name = "rafamadriz/friendly-snippets";
    }).outPath == pkgs.vimPlugins.friendly-snippets.outPath) true;
  test-dependency-explicit-mapping = testLib.testEval "dependency-explicit-mapping"
    ((resolver.resolveDependency { pluginSource = "latest"; } {
      name = "saghen/blink.compat";
    }).outPath == pkgs.vimPlugins.blink-compat.outPath) true;
}
