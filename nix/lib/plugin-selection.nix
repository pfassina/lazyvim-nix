{ lib }:
{
  # Include dependency metadata even when the dependency has no top-level spec.
  withDependencies = pluginData: selected:
    let
      byName = lib.listToAttrs (map (spec: lib.nameValuePair spec.name spec) pluginData);
      visit = seen: pending: result:
        if pending == [] then result else
        let
          spec = builtins.head pending;
          rest = builtins.tail pending;
          dependencies = spec.dependencies or [];
          missing = lib.unique (lib.filter (name: !(builtins.elem name seen))
            (if builtins.isList dependencies then dependencies else []));
          added = map (name: (byName.${name} or { inherit name; }) // {
            dependencyOnly = true;
          }) missing;
        in visit (seen ++ missing) (rest ++ added) (result ++ added);
    in visit (map (spec: spec.name) selected) selected selected;
}
