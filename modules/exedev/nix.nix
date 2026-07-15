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
        extra-substituters = https://nix-community.cachix.org
        trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWGuJSngDLi9PB0dxEIoH5U8vKf1c=
        extra-trusted-public-keys = nix-community.cachix.org-1:6B2OlI2s8yNqBi0A5HheB1jO31v3eB/OlG5RAnFiRbQ=
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
        # Seed a default nixpkgs channel if none is configured.
        # Using nixos-25.11 to match the flake's pinned nixpkgs revision.
        if ! ${pkgs.nix}/bin/nix-channel --list 2>/dev/null | grep -q nixpkgs; then
          ${pkgs.nix}/bin/nix-channel --add https://nixos.org/channels/nixos-25.11 nixpkgs 2>&1
          ${pkgs.nix}/bin/nix-channel --update 2>&1 || true
        fi
      '';
    };
    s6.services.nix-daemon = {
      dependencies = [
        "base"
        "nix-db"
      ];
      # must use the local store; inheriting NIX_REMOTE=daemon (image.env) makes
      # it connect to its own socket and fork-bomb the store until PIDs exhaust.
      run = "NIX_REMOTE= exec ${pkgs.nix}/bin/nix-daemon --daemon";
    };
  };
}
