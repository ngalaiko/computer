{
  pkgs,
  nixSource,
  # the nix the image ships; from nixSource so it matches docker.nix below
  nixPackage ? pkgs.nix,
  imageName ? "computer.exe",
}:

let
  inherit (pkgs) lib runCommand;
  profile = "/nix/var/nix/profiles/default";

  labels = {
    "org.opencontainers.image.title" = "computer.exe";
    "org.opencontainers.image.description" = "exe.dev image: s6-overlay, OpenSSH, Nix, and Shelley";
    # read by exe.dev at VM creation (login user + enables Shelley/its UI icon)
    "exe.dev/login-user" = "exedev";
    "exe.dev/install-shelley" = "true";
  };

  basePackages = with pkgs; [
    bashInteractive
    coreutils-full
    findutils
    gnugrep
    gnused
    iproute2
    procps
    tzdata
    util-linux
  ];

  # Each component is a dir returning `{ packages; rootfs?; }`. s6-overlay first
  # so its tree is in place before the rest overlay on. Users live in users.nix.
  components = map (m: import m { inherit pkgs; }) [
    ./s6-overlay
    ./sshd
    ./shelley
  ];
  packages = basePackages ++ lib.concatMap (c: c.packages or [ ]) components;

  usersRootfs = import ./users.nix { inherit pkgs; };
  rootfsDirs = lib.filter (d: d != null) (map (c: c.rootfs or null) components) ++ [
    usersRootfs
    ./rootfs
  ];

  # All rootfs trees overlaid at /. `cp -a` preserves s6-overlay's symlinks;
  # `chmod -R u+w` after each copy lets the next merge into from-store dirs.
  rootfs = runCommand "exedev-rootfs" { } (
    ''
      mkdir -p $out
    ''
    + lib.concatMapStrings (d: ''
      cp -a ${d}/. $out/
      chmod -R u+w $out
    '') rootfsDirs
    + ''
      chmod 0755 $out/etc/s6-overlay/s6-rc.d/*/run 2>/dev/null || true
      chmod 0755 $out/etc/s6-overlay/scripts/* 2>/dev/null || true
      chmod 0755 $out/init-wrapper

      # mountpoints for init-wrapper (covers a read-only /dev)
      mkdir -p $out/proc $out/dev/pts

      mkdir -p $out/bin $out/usr
      ln -sfn ${pkgs.bashInteractive}/bin/bash $out/bin/sh
      ln -sfn ${profile}/share $out/usr/share
      ln -sfn ${pkgs.iana-etc}/etc/protocols $out/etc/protocols
      ln -sfn ${pkgs.iana-etc}/etc/services $out/etc/services
    ''
  );

  nixBase = pkgs.callPackage "${nixSource}/docker.nix" {
    name = "computer-exe-bootstrap";
    tag = "latest";
    nix = nixPackage;
    bundleNixpkgs = false;
    extraPkgs = packages;
    maxLayers = 110;
    nixConf = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      sandbox = false;
      build-users-group = "nixbld";
      trusted-users = [
        "root"
        "exedev"
      ];
      substituters = [ "https://cache.nixos.org/" ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWGuJSngDLi9PB0dxEIoH5U8vKf1c="
      ];
    };
    Cmd = [ "/init-wrapper" ];
    Labels = labels;
  };
in
pkgs.dockerTools.buildLayeredImage {
  name = imageName;
  tag = "latest";
  created = "1970-01-01T00:00:01Z";
  fromImage = nixBase;
  contents = [ rootfs ];
  maxLayers = 120;
  config = {
    Cmd = [ "/init-wrapper" ];
    User = "0:0";
    Env = [
      "PATH=/command:${profile}/bin:${profile}/sbin:/bin:/usr/bin"
      "NIX_REMOTE=daemon"
      "SSL_CERT_FILE=${profile}/etc/ssl/certs/ca-bundle.crt"
      "NIX_SSL_CERT_FILE=${profile}/etc/ssl/certs/ca-bundle.crt"
      "USER=root"
      "HOME=/root"
    ];
    ExposedPorts = {
      "22/tcp" = { };
      "9999/tcp" = { };
    };
    WorkingDir = "/home/exedev";
    Labels = labels;
  };
}
