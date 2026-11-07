{ pkgs, testLib, ... }:
let
  inherit (pkgs) lib;
  data = builtins.fromJSON (builtins.readFile ../../data/plugins.json);
  resolver = import ../../nix/lib/plugin-resolution.nix {
    inherit lib pkgs;
    pluginMappings = {};
    ignoreBuildNotifications = true;
  };
  lazyvim = resolver.resolvePlugin { pluginSource = "latest"; }
    (lib.findFirst (p: p.name == "LazyVim/LazyVim") null data.plugins);
  defaults = import ../../nix/lib/default-extras.nix { inherit pkgs; };
  inspect = options: explicitExtras: defaults.resolve {
    inherit lazyvim explicitExtras;
    neovim = pkgs.neovim-unwrapped;
    optionsFile = pkgs.writeText "test-options.lua" options;
  };
  select = options: explicitExtras: (inspect options explicitExtras).enabled;
  fresh = select "" [];
  explicit = select "" [ "coding.nvim-cmp" ];
  override = select ''vim.g.lazyvim_cmp = table.concat({"nvim", "cmp"}, "-")'' [ "coding.blink" ];
  picker = select ''vim.g.lazyvim_picker = "telescope"; vim.g.lazyvim_explorer = "neo-tree"'' [];
  callback = select ''
    vim.api.nvim_create_autocmd("User", {
      pattern = "LazyVimOptions",
      callback = function() vim.g.lazyvim_cmp = "nvim-cmp" end,
    })
  '' [];
  completionPlugins = (inspect ''vim.g.lazyvim_cmp = "nvim-cmp"'' []).plugins;
in {
  test-default-extras-fresh-install = testLib.testEval "default-extras-fresh-install"
    (builtins.elem "coding.blink" fresh && builtins.elem "editor.snacks_picker" fresh
      && builtins.elem "editor.snacks_explorer" fresh && !(builtins.elem "coding.nvim-cmp" fresh)) true;
  test-default-extras-explicit-completion = testLib.testEval "default-extras-explicit-completion"
    (builtins.elem "coding.nvim-cmp" explicit && !(builtins.elem "coding.blink" explicit)) true;
  test-default-extras-executable-options-precedence = testLib.testEval "default-extras-executable-options-precedence"
    (builtins.elem "coding.nvim-cmp" override && !(builtins.elem "coding.blink" override)) true;
  test-default-extras-picker-explorer = testLib.testEval "default-extras-picker-explorer"
    (builtins.elem "editor.telescope" picker && builtins.elem "editor.neo-tree" picker
      && !(builtins.elem "editor.snacks_picker" picker)) true;
  test-default-extras-options-event = testLib.testEval "default-extras-options-event"
    (builtins.elem "coding.nvim-cmp" callback && !(builtins.elem "coding.blink" callback)) true;
  test-default-extras-nested-merged-dependencies = testLib.testEval "default-extras-nested-merged-dependencies"
    (builtins.elem "garymjr/nvim-snippets" completionPlugins
      && builtins.elem "rafamadriz/friendly-snippets" completionPlugins) true;
}
