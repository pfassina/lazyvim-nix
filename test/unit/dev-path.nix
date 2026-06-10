# Unit tests for dev path creation and symlink handling
# Imports the real nix/lib/dev-path.nix, builds an actual dev path derivation
# from fake plugin packages, and inspects the resulting symlinks.
{ pkgs, testLib, ... }:

let
  inherit (pkgs) lib;

  fixtureMappings = {
    "nvim-mini/mini.ai" = { package = "mini-nvim"; module = "mini.ai"; };
    "nvim-mini/mini.pairs" = { package = "mini-nvim"; module = "mini.pairs"; };
    "folke/lazy.nvim" = "lazy-nvim";
  };

  # The real dev path library under test
  devPathLib = import ../../nix/lib/dev-path.nix {
    inherit lib pkgs;
    pluginMappings = fixtureMappings;
  };

  inherit (devPathLib) createDevPath getRepoName generateDevPluginSpecs;

  # Cheap stand-ins for resolved plugin packages
  fakePlugin = name: pkgs.runCommand "fake-${name}" {} ''
    mkdir -p $out
    echo "${name}" > $out/marker
  '';
  fakeLazy = fakePlugin "lazy-nvim";
  fakeLsp = fakePlugin "nvim-lspconfig";
  fakeMini = fakePlugin "mini-nvim";

  # Specs cover: regular plugins, two modules of one multi-module package, a
  # duplicate entry for the same module (must deduplicate), and an unresolved
  # plugin (null, must be filtered out).
  devPathSpecs = [
    { name = "folke/lazy.nvim"; }
    { name = "neovim/nvim-lspconfig"; }
    { name = "nvim-mini/mini.ai"; }
    { name = "nvim-mini/mini.pairs"; }
    { name = "nvim-mini/mini.ai"; }
    { name = "owner/unresolved-plugin"; }
  ];
  devPathResolved = [ fakeLazy fakeLsp fakeMini fakeMini fakeMini null ];

  devPath = createDevPath devPathSpecs devPathResolved;

  # generateDevPluginSpecs must exclude treesitter plugins and unresolved ones
  devSpecs = generateDevPluginSpecs devPathLib [
    { name = "folke/lazy.nvim"; }
    { name = "nvim-treesitter/nvim-treesitter"; }
    { name = "nvim-treesitter/nvim-treesitter-textobjects"; }
    { name = "owner/unresolved-plugin"; }
  ] [ fakeLazy fakeMini fakeMini null ];

in {
  # getRepoName: real function edge cases
  test-get-repo-name-standard = testLib.testEval
    "get-repo-name-standard"
    (getRepoName "folke/lazy.nvim")
    "lazy.nvim";

  test-get-repo-name-with-dots = testLib.testEval
    "get-repo-name-with-dots"
    (getRepoName "nvim-telescope/telescope.nvim")
    "telescope.nvim";

  test-get-repo-name-with-hyphens = testLib.testEval
    "get-repo-name-with-hyphens"
    (getRepoName "owner/repo-with-hyphens")
    "repo-with-hyphens";

  test-get-repo-name-no-owner = testLib.testEval
    "get-repo-name-no-owner"
    (getRepoName "single-name")
    "single-name";

  # createDevPath: regular plugins are linked by repo name, multi-module
  # plugins by module name
  test-dev-path-creates-symlinks = testLib.runTest "dev-path-creates-symlinks"
    ''[ -L "${devPath}/lazy.nvim" ] && [ -L "${devPath}/nvim-lspconfig" ] && [ -L "${devPath}/mini.ai" ] && [ -L "${devPath}/mini.pairs" ]'';

  # createDevPath: symlinks point at the resolved plugin packages
  test-dev-path-links-point-to-plugins = testLib.runTest "dev-path-links-point-to-plugins"
    ''[ "$(readlink "${devPath}/lazy.nvim")" = "${fakeLazy}" ] && [ "$(readlink "${devPath}/mini.ai")" = "${fakeMini}" ] && [ "$(readlink "${devPath}/mini.pairs")" = "${fakeMini}" ]'';

  # createDevPath: duplicate module entries are deduplicated and unresolved
  # (null) plugins are dropped, so exactly 4 links remain
  test-dev-path-dedup-and-null-filtering = testLib.runTest "dev-path-dedup-and-null-filtering"
    ''[ "$(ls "${devPath}" | wc -l)" -eq 4 ]'';

  # generateDevPluginSpecs: produces lazy.nvim dev specs in the expected format
  test-dev-specs-format = testLib.testEval
    "dev-specs-format"
    (builtins.head devSpecs)
    ''{ "lazy.nvim", dev = true, pin = true },'';

  # generateDevPluginSpecs: treesitter plugins and unresolved plugins are
  # excluded, leaving only the one regular resolved plugin
  test-dev-specs-exclusions = testLib.testEval
    "dev-specs-exclusions"
    (builtins.length devSpecs)
    1;
}
