# s6-overlay (/init + supervision) plus ./rootfs, which holds the ENTIRE service
# graph (etc/s6-overlay/s6-rc.d/) — the one place it's declared.
# tar without -p: the Nix store can't hold s6-overlay-suexec's setuid bit.
{ pkgs }:
let
  version = "3.2.1.0";
  url = f: "https://github.com/just-containers/s6-overlay/releases/download/v${version}/${f}";
  noarch = pkgs.fetchurl {
    url = url "s6-overlay-noarch.tar.xz";
    sha256 = "42e038a9a00fc0fef70bf0bc42f625a9c14f8ecdfe77d4ad93281edf717e10c5";
  };
  arch =
    {
      x86_64-linux = pkgs.fetchurl {
        url = url "s6-overlay-x86_64.tar.xz";
        sha256 = "8bcbc2cada58426f976b159dcc4e06cbb1454d5f39252b3bb0c778ccf71c9435";
      };
      aarch64-linux = pkgs.fetchurl {
        url = url "s6-overlay-aarch64.tar.xz";
        sha256 = "c8fd6b1f0380d399422fc986a1e6799f6a287e2cfa24813ad0b6a4fb4fa755cc";
      };
    }
    .${pkgs.stdenv.hostPlatform.system}
      or (throw "unsupported s6-overlay platform: ${pkgs.stdenv.hostPlatform.system}");

  overlay = pkgs.runCommand "s6-overlay-${version}" { nativeBuildInputs = [ pkgs.gnutar pkgs.xz ]; } ''
    mkdir -p $out
    tar -C $out -Jxf ${noarch}
    tar -C $out -Jxf ${arch}
    cp -R ${./rootfs}/. $out/
  '';
in
{
  packages = [ ];
  rootfs = overlay;
}
