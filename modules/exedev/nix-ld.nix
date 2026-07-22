{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;

  # Standard libraries exposed to dynamically-linked non-Nix binaries.
  nix-ld-libraries = pkgs.buildEnv {
    name = "nix-ld-libraries";
    pathsToLink = [ "/lib" ];
    paths = map lib.getLib [
      pkgs.zlib
      pkgs.zstd
      pkgs.stdenv.cc.cc
      pkgs.curl
      pkgs.openssl
      pkgs.attr
      pkgs.libssh
      pkgs.bzip2
      pkgs.libxml2
      pkgs.acl
      pkgs.libsodium
      pkgs.util-linux
      pkgs.xz
    ];
    extraPrefix = "/share/nix-ld";
    ignoreCollisions = true;
    postBuild = ''
      mkdir -p $out/share/nix-ld/lib
      ln -s ${pkgs.stdenv.cc.bintools.dynamicLinker} $out/share/nix-ld/lib/ld.so
    '';
  };

  # FHS path where foreign ELF binaries expect their loader; nix-ld installs a
  # shim there. Arch-specific — the release pushes both x86_64 and aarch64, so
  # unknown systems fail loud rather than baking the wrong path.
  ldsoPath =
    {
      "x86_64-linux" = "/lib64/ld-linux-x86-64.so.2";
      "aarch64-linux" = "/lib/ld-linux-aarch64.so.1";
    }
    .${pkgs.stdenv.hostPlatform.system};
in
{
  options.nix-ld.enable = mkEnableOption "nix-ld for running dynamically-linked non-Nix binaries";

  config = mkIf config.nix-ld.enable {
    image.packages = [
      pkgs.nix-ld
      nix-ld-libraries
    ];

    image.fakeRootCommands = ''
      mkdir -p .${builtins.dirOf ldsoPath}
      ln -sfn ${pkgs.nix-ld}/libexec/nix-ld .${ldsoPath}
    '';

    # nix-ld reads these to find the real loader + libraries. image.env covers
    # PID1-descended processes (the open-webui service); ssh scrubs the env, so
    # login shells re-export via /etc/profile (cf. profile.d/nix.sh).
    image.env = [
      "NIX_LD=${nix-ld-libraries}/share/nix-ld/lib/ld.so"
      "NIX_LD_LIBRARY_PATH=${nix-ld-libraries}/share/nix-ld/lib"
    ];

    environment.etc."profile.d/nix-ld.sh".text = ''
      export NIX_LD=${nix-ld-libraries}/share/nix-ld/lib/ld.so
      export NIX_LD_LIBRARY_PATH=${nix-ld-libraries}/share/nix-ld/lib
    '';
  };
}
