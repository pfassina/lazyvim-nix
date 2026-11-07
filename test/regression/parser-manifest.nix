{ pkgs, testLib, moduleUnderTest }:
let
  inherit (pkgs) lib;
  manifest = builtins.fromJSON (builtins.readFile ../../data/parser-manifest.json);
  data = import ../../nix/lib/data-loading.nix { inherit lib pkgs; };
  resolver = import ../../nix/lib/plugin-resolution.nix {
    inherit lib pkgs;
    inherit (data) pluginMappings;
    ignoreBuildNotifications = true;
  };
  spec = lib.findFirst (p: p.name == "nvim-treesitter/nvim-treesitter") null data.pluginData.plugins;
  resolve = pluginSpec: resolver.resolvePlugin { pluginSource = "latest"; } pluginSpec;
  check = plugin: import ../../nix/lib/parser-coherence.nix { inherit manifest plugin; };
  moduleAssertions = strategy: (moduleUnderTest {
    inherit lib pkgs;
    config = {
      home.homeDirectory = "/nonexistent";
      programs.lazyvim = {
        enable = true;
        appName = "nvim";
        pluginSource = strategy;
        ignoreBuildNotifications = true;
        extras = {};
      };
    };
  }).config.content.assertions;
  overridden = field: resolve (spec // {
    version_info = spec.version_info // { ${field} = "different-revision"; };
  });
in {
  test-parser-manifest-current = testLib.testEval "parser-manifest-current"
    (import ../../scripts/check-parser-manifest.nix { inherit pkgs; }) true;
  test-parser-manifest-module-latest = testLib.testEval "parser-manifest-module-latest"
    (builtins.all (a: a.assertion) (moduleAssertions "latest")) true;
  test-parser-manifest-module-nixpkgs = testLib.testEval "parser-manifest-module-nixpkgs"
    (moduleAssertions "nixpkgs" == []) true;
  test-parser-manifest-mismatch = testLib.testEval "parser-manifest-mismatch"
    (check { src.rev = "539abf6da5ee8702e37b82cc953131dadd570da2"; }).assertion false;
  test-parser-manifest-version-overrides-commit = testLib.testEval "parser-manifest-version-overrides-commit"
    (check (overridden "lazyvim_version")).assertion false;
  test-parser-manifest-tag-overrides-commit = testLib.testEval "parser-manifest-tag-overrides-commit"
    (check (resolve (spec // {
      version_info = builtins.removeAttrs spec.version_info [ "lazyvim_version" ] // { tag = "different-tag"; };
    }))).assertion false;
  test-parser-manifest-latest-version-overrides-commit = testLib.testEval "parser-manifest-latest-version-overrides-commit"
    (check (resolve (spec // {
      version_info = builtins.removeAttrs spec.version_info [ "lazyvim_version" "tag" ] // { latest_version = "different-version"; };
    }))).assertion false;
  test-parser-manifest-missing-revision = testLib.testEval "parser-manifest-missing-revision"
    (check { src = {}; }).assertion false;
  test-parser-manifest-extraction-cache = pkgs.runCommand "test-parser-manifest-extraction-cache" {
    nativeBuildInputs = [ pkgs.neovim pkgs.jq ];
  } ''
    export HOME="$TMPDIR"
    mkdir -p source/lua/nvim-treesitter
    cat > source/lua/nvim-treesitter/parsers.lua <<'EOF'
    return { lua = { install_info = { url = "https://example.invalid/parser", revision = "parser-revision" } } }
    EOF
    cat > existing.json <<'EOF'
    {"nvim_treesitter_commit":"old-plugin-commit","parsers":{"lua":{"url":"https://example.invalid/parser","revision":"parser-revision","sha256":"cached-parser-hash"}}}
    EOF
    nvim --headless -u NONE -l ${../../scripts/extract-parser-manifest.lua} \
      source existing.json result.json 5cb0114e6242625db56dd6440e945ed1ece10bc7
    jq -e '.nvim_treesitter_commit == "5cb0114e6242625db56dd6440e945ed1ece10bc7"
      and .parsers.lua.sha256 == "cached-parser-hash"' result.json
    if nvim --headless -u NONE -l ${../../scripts/extract-parser-manifest.lua} \
      source existing.json missing-commit.json; then
      echo "Extraction accepted a missing plugin commit"
      exit 1
    fi
    test ! -e missing-commit.json
    touch "$out"
  '';
  test-parser-manifest-release-cache-failure = pkgs.runCommand "test-parser-manifest-release-cache-failure" {
    nativeBuildInputs = [ pkgs.bash pkgs.jq pkgs.gnutar pkgs.gnugrep ];
  } ''
    mkdir -p repo/scripts repo/data bin
    cp ${../../scripts/update-plugins.sh} repo/scripts/update-plugins.sh
    cache="$PWD/repo/tmp/update-cache"
    mkdir -p "$cache/LazyVim/.git" "$cache/starter/.git" "$cache/starter/lua/config"
    echo 'return {}' > "$cache/starter/lua/config/lazy.lua"
    release="$cache/releases/0000000000000000000000000000000000000000-2-noverify"
    mkdir -p "$release"
    echo '{"plugins":[{"name":"nvim-treesitter/nvim-treesitter","version_info":{"commit":"5cb0114e6242625db56dd6440e945ed1ece10bc7"}}]}' > "$release/plugins.json"
    echo '{}' > "$release/dependencies.json"
    echo '{}' > "$release/treesitter.json"
    echo '{"nvim_treesitter_commit":"539abf6da5ee8702e37b82cc953131dadd570da2","parsers":{}}' > "$release/parser-manifest.json"
    cat > bin/git <<'EOF'
    #!/usr/bin/env bash
    if [ "$1" = clone ]; then exit 1; fi
    case "$3" in
      tag) echo v1 ;;
      rev-parse) echo 0000000000000000000000000000000000000000 ;;
      archive) tar -cf - --files-from /dev/null ;;
    esac
    EOF
    chmod +x bin/git
    export PATH="$PWD/bin:$PATH"
    if bash repo/scripts/update-plugins.sh > output.log 2>&1; then
      echo "Update accepted a stale release-cache manifest after clone failure"
      exit 1
    fi
    grep -F "Using cached metadata" output.log
    grep -F "Error: Failed to clone nvim-treesitter" output.log
    cmp repo/data/parser-manifest.json "$release/parser-manifest.json"
    touch "$out"
  '';
}
