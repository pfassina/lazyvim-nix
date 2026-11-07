# The default completion extra needs its native matcher as well as Lua files.
{ lib, pkgs }:
{ src, version }:
let
  fuzzy = pkgs.rustPlatform.buildRustPackage {
    pname = "blink-cmp-fuzzy";
    inherit src version;
    cargoLock.lockFile = "${src}/Cargo.lock";
    nativeBuildInputs = [ pkgs.git ];
    env = {
      RUSTC_BOOTSTRAP = true;
      RUSTFLAGS = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin
        "-C link-arg=-undefined -C link-arg=dynamic_lookup";
    };
  };
  extension = pkgs.stdenv.hostPlatform.extensions.sharedLibrary;
in pkgs.vimUtils.buildVimPlugin {
  pname = "blink.cmp";
  inherit src version;
  preInstall = ''
    mkdir -p target/release
    ln -s ${fuzzy}/lib/libblink_cmp_fuzzy${extension} target/release/libblink_cmp_fuzzy${extension}
  '';
  doCheck = false;
}
