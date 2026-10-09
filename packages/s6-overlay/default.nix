# tar without -p: the Nix store can't hold s6-overlay-suexec's setuid bit.
{ pkgs }:
let
  version = "3.2.3.2";
  url = f: "https://github.com/just-containers/s6-overlay/releases/download/v${version}/${f}";
  noarch = pkgs.fetchurl {
    url = url "s6-overlay-noarch.tar.xz";
    sha256 = "5379750ed30a84bbd2e2dd74847ba6b5bd29cd0b2e3ea2ec58049b57eb2eda12";
  };
  arch =
    {
      x86_64-linux = pkgs.fetchurl {
        url = url "s6-overlay-x86_64.tar.xz";
        sha256 = "e6befcc96a437a3831386ecfc51808c5d3e939dc5fe3c02ae9284599e8aa2408";
      };
      aarch64-linux = pkgs.fetchurl {
        url = url "s6-overlay-aarch64.tar.xz";
        sha256 = "b17f17a82e7a515c682a91edaf2ffdabb73f891981b6c1fd712115693a2f8b4c";
      };
    }
    .${pkgs.stdenv.hostPlatform.system}
      or (throw "unsupported s6-overlay platform: ${pkgs.stdenv.hostPlatform.system}");
in
pkgs.runCommand "s6-overlay-${version}"
  {
    nativeBuildInputs = [
      pkgs.gnutar
      pkgs.xz
    ];
  }
  ''
    mkdir -p $out
    tar -C $out -Jxf ${noarch}
    tar -C $out -Jxf ${arch}
  ''
