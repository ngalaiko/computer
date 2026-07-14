{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  profile = "/nix/var/nix/profiles/default";

  nixbld = lib.listToAttrs (
    map (n: {
      name = "nixbld${toString n}";
      value = {
        uid = 30000 + n;
        group = "nixbld";
        description = "Nix build user ${toString n}";
        locked = true;
      };
    }) (lib.range 1 32)
  );

  # scoped to image.packages, never image.rootPaths (the loader is a rootPaths
  # service — feeding rootPaths back into the closure is an eval cycle).
  storeReg = pkgs.closureInfo { rootPaths = config.image.packages; };
in
{
  options.nix.enable = mkOption {
    type = types.bool;
    default = true;
    description = "Ship a Nix daemon over a registered store (runtime installs).";
  };

  config = lib.mkIf config.nix.enable {
    image.packages = [ pkgs.nix ];

    image.env = [
      "PATH=/command:${profile}/bin:${profile}/sbin:/bin:/sbin:/usr/bin"
      "NIX_REMOTE=daemon"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "GIT_SSL_CAINFO=/etc/ssl/certs/ca-bundle.crt"
      "USER=root"
      "HOME=/root"
    ];

    users.users = nixbld;
    users.groups.nixbld = {
      gid = 30000;
      members = lib.attrNames nixbld;
    };

    environment.etc = {
      "nix/nix.conf".text = ''
        experimental-features = nix-command flakes
        build-users-group = nixbld
        trusted-users = root exedev hermes
        substituters = https://cache.nixos.org/
        trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWGuJSngDLi9PB0dxEIoH5U8vKf1c=
        sandbox = false
      '';
      # sshd resets the env, so login shells re-source this via /etc/profile.
      "profile.d/nix.sh".text = ''
        export PATH="$HOME/.nix-profile/bin:${profile}/bin:${profile}/sbin:$PATH"
        export NIX_REMOTE=daemon
        export NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
      '';
    };

    s6.services.nix-db = {
      type = "oneshot";
      run = ''
        mkdir -p /nix/var/nix/profiles/per-user /nix/var/nix/gcroots/per-user
        if [ ! -f /nix/var/nix/db/db.sqlite ]; then
          NIX_REMOTE= ${pkgs.nix}/bin/nix-store --load-db < ${storeReg}/registration
        fi
      '';
    };
    s6.services.nix-daemon = {
      dependencies = [
        "base"
        "nix-db"
      ];
      run = "exec ${pkgs.nix}/bin/nix-daemon --daemon";
    };
  };
}
