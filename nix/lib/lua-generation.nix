# Public Lua-generation helpers, exposed via the flake's top-level `lib`
# output (issue #73). They generate lazy.nvim plugin spec Lua code from Nix
# attrsets, so `programs.lazyvim.plugins` values can be written as Nix
# instead of raw Lua strings. Embed Lua code (e.g. functions) inside a spec
# with lib.generators.mkLuaInline.
#
# Not related to the internal `lazyConfig` in config-generation.nix, which
# patches the lazy.nvim bootstrap config and is not flake-exported.
{ lib }:

rec {
  # Render a single lazy.nvim plugin spec table from an attrset.
  # The `plugin` attr becomes the table's bare positional string
  # ({ "owner/repo", ... }), which toLua cannot express on its own (it has no
  # syntax for mixed positional/keyed tables). `indent` only controls
  # formatting and is not part of the spec.
  lazyPlugin =
    spec@{ indent ? "", ... }:
    let
      attrs = removeAttrs spec [ "plugin" "indent" ];
      lua = lib.generators.toLua { inherit indent; } attrs;
    in
    if !(spec ? plugin) then
      lua
    else if attrs == { } then
      "{ ${builtins.toJSON spec.plugin} }"
    else
      # toJSON escapes the plugin name the same way toLua escapes every other
      # string. substring with negative length means "to the end", so this
      # splices the plugin name in as the table's first entry.
      "{\n${indent}  ${builtins.toJSON spec.plugin}," + builtins.substring 1 (-1) lua;

  # Generate a complete plugin file body ("return ...") from a single spec
  # attrset or a list of spec attrsets, suitable as a
  # `programs.lazyvim.plugins.<name>` value.
  lazyConfig =
    specs:
    "return "
    + (
      if builtins.isAttrs specs then
        lazyPlugin specs
      else
        lib.generators.toLua { } (
          map (spec: lib.generators.mkLuaInline (lazyPlugin (spec // { indent = "  "; }))) specs
        )
    );
}
