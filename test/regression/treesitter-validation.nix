{ pkgs, ... }:
let
  fixtures = import ../fixtures/treesitter-validation.nix { inherit pkgs; };
  # Execute the real derivation's builder in a child shell so an expected
  # failure can be asserted without making runAll depend on a failing output.
  expectFailure = name: drv: messages:
    drv.overrideAttrs (old: {
      name = "test-treesitter-${name}";
      buildCommand = ''
        if ${pkgs.bash}/bin/bash ${pkgs.writeText "treesitter-${name}-builder" ''
          set -e
          ${old.buildCommand}
        ''} > validation.log 2>&1; then
          cat validation.log
          echo 'Expected treesitter validation to fail'
          exit 1
        fi
        cat validation.log
        ${pkgs.lib.concatMapStringsSep "\n" (message: ''
          grep -F ${pkgs.lib.escapeShellArg message} validation.log
        '') messages}
        touch "$out"
      '';
    });
in {
  test-treesitter-validation-valid = fixtures.valid;
  test-treesitter-validation-invalid-query = expectFailure "invalid-query" fixtures.invalid [
    "Treesitter validation failed:"
    "lua/regression:"
    "lua/second:"
    "Invalid node type"
    "lua/highlights:"
  ];
  test-treesitter-validation-parser-load = expectFailure "parser-load" fixtures.unloadable [
    "Treesitter validation failed:"
    "broken/parser:"
  ];
}
