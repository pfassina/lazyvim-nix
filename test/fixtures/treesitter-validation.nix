{ pkgs ? import <nixpkgs> { } }:
let
  validate = import ../../nix/lib/validate-treesitter.nix { inherit pkgs; };
  parsers = pkgs.vimPlugins.nvim-treesitter.grammarPlugins.lua;
  validQueries = pkgs.runCommand "treesitter-valid-queries" { } ''
    mkdir -p "$out/lua" "$out/query_base"
    echo '; inherits: query_base' > "$out/lua/highlights.scm"
    echo '(identifier) @variable' > "$out/query_base/highlights.scm"
    echo '(identifier) @variable' > "$out/lua/regression.scm"
  '';
  invalidQueries = pkgs.runCommand "treesitter-invalid-queries" { } ''
    cp -r ${validQueries} "$out"
    chmod -R u+w "$out"
    echo '(lazyvim_nonexistent_node) @variable' > "$out/lua/regression.scm"
    echo '(another_nonexistent_node) @variable' > "$out/lua/second.scm"
    echo '(inherited_nonexistent_node) @variable' > "$out/query_base/highlights.scm"
  '';
  brokenParsers = pkgs.runCommand "treesitter-broken-parsers" { } ''
    mkdir -p "$out/parser"
    echo 'not a shared library' > "$out/parser/broken.so"
  '';
  check = parsers: queries: validate {
    neovim = pkgs.neovim-unwrapped;
    inherit parsers queries;
  };
in {
  valid = check parsers validQueries;
  invalid = check parsers invalidQueries;
  unloadable = check brokenParsers validQueries;
  # Reproduce the old module path: filtering/linking alone accepts invalid queries.
  baseline = pkgs.runCommand "treesitter-unvalidated-queries" { } ''
    ln -s ${invalidQueries} "$out"
  '';
  inherit parsers;
}
