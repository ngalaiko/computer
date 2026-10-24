{
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [
    ../../modules/nixos/exedev
    inputs.home-manager.nixosModules.home-manager
    ./users
  ];

  system.stateVersion = "26.05";

  nixpkgs.overlays = [ (import ../../overlay.nix { inherit inputs; }) ];
  # Only these unfree packages, here and in pkgs.unstable.
  nixpkgs.config.allowUnfreePredicate = p: builtins.elem (lib.getName p) [ "amp-cli" ];

  exedev.image = {
    name = "computer.exe";
    labels = {
      "org.opencontainers.image.title" = "computer.exe";
      "org.opencontainers.image.description" = "exe.dev image: NixOS and Tailscale SSH";
      "exe.dev/login-user" = "nikita";
    };
  };

  environment.systemPackages = with pkgs; [
    curl
    iproute2
    openssh # ssh client + ssh-keygen (git/jj signing); no sshd server
  ];

  # Accounts are passwordless; access is Tailscale SSH and exe.dev's own ssh.
  users.mutableUsers = false;
  users.allowNoPasswordLogin = true;
  security.sudo.wheelNeedsPassword = false;

  # The bootstrap image needs authentication before evaluating the Rex flake.
  # Provision the root-readable file outside Nix; restore it with the homes.
  nix.settings = {
    netrc-file = "/etc/nix/rex.netrc";
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  programs.nix-ld = {
    enable = true;
    libraries = map lib.getLib [
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
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    # restored homes may hold plain copies of managed files.
    backupFileExtension = "backup";
    extraSpecialArgs = { inherit inputs; };
  };

  # One tailnet node, `exedev`: ssh + the public ingress funnel on its own
  # name. Node state lives in /var/lib/tailscale and is not backed up, so a
  # fresh disk registers a new node; the ephemeral key retires the old one.
  services.tailscale = {
    enable = true;
    authKeyFile = "/var/lib/tailscale/authkey";
    extraUpFlags = [
      "--ssh"
      "--hostname=exedev"
      "--advertise-tags=tag:exedev"
      "--accept-dns=false"
    ];
    # re-applied on every boot; up flags apply only at login.
    extraSetFlags = [ "--hostname=exedev" ];
  };
  systemd.services.tailscaled = {
    wants = [ "backup-restore.service" ];
    after = [ "backup-restore.service" ];
    # exe.dev's /dev has no tun node.
    preStart = ''
      if [ ! -e /dev/net/tun ]; then
        mkdir -p /dev/net
        ${pkgs.coreutils}/bin/mknod /dev/net/tun c 10 200
      fi
    '';
  };
  exedev.backup.paths = [
    "/var/lib/tailscale/authkey"
    "/etc/nix/rex.netrc"
  ];

  # Public path-routed ingress via node Funnel:
  # https://exedev.<tailnet>.ts.net/<tenant>/. World-reachable with NO auth,
  # unlike the exe.dev-shared 8080, which exe.dev gates. Node-named, so the URL
  # can churn when the machine is recreated; exe.dev's share stays the stable
  # public path. Reconstructed on every boot: `serve reset` makes this list
  # authoritative.
  systemd.services.tailscale-serve = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "tailscaled-autoconnect.service" ];
    after = [ "tailscaled-autoconnect.service" ];
    path = [ pkgs.tailscale ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      tailscale serve reset
      tailscale funnel --bg --https=443 localhost:8080
    '';
  };

  # tenants registered per-user in hosts/exedev/users/*.nix.
  services.ingress.enable = true;
}
