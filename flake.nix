{
  description = "A Nix flake for LazyVim that just works™";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in
    flake-utils.lib.eachSystem supportedSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.writeShellScriptBin "lazyvim-update" ''
          ${pkgs.bash}/bin/bash ${./scripts/update-plugins.sh}
        '';

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            neovim
            lua
            jq
            git
            ripgrep
            fd
            nix-prefetch-git
          ];
        };
      })
    //
    {
      homeManagerModules.default = ./nix/module.nix;
      homeManagerModules.lazyvim = ./nix/module.nix;

      overlays.default = final: prev: {
        lazyvimPluginData = builtins.fromJSON (builtins.readFile ./data/plugins.json);
        lazyvimPluginMappings = builtins.fromJSON (builtins.readFile ./data/mappings.json);
        lazyvimExtrasMetadata = builtins.fromJSON (builtins.readFile ./data/extras.json);
        lazyvimOverrides = import ./nix/overrides/default.nix { pkgs = final; };
      };
    };
}