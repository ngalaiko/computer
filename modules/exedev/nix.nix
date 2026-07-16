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

  # resolve via root.inputs — plain .nodes.nixpkgs can be another input's pin
  # (node names shuffle on lock updates; ours is currently nixpkgs_2). The FOD
  # makes the daemon verify narHash at build time.
  nixpkgsLock =
    let
      lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
    in
    lock.nodes.${lock.nodes.root.inputs.nixpkgs}.locked;
  nixpkgsSrc = pkgs.fetchzip {
    url = "https://github.com/${nixpkgsLock.owner}/${nixpkgsLock.repo}/archive/${nixpkgsLock.rev}.tar.gz";
    hash = nixpkgsLock.narHash;
  };

  # scoped to image.packages, never image.rootPaths (the loader is a rootPaths
  # service — feeding rootPaths back into the closure is an eval cycle).
  # nixpkgsSrc must be db-registered or flake refs reject it as an invalid path.
  storeReg = pkgs.closureInfo { rootPaths = config.image.packages ++ [ nixpkgsSrc ]; };
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
      "NIX_PATH=nixpkgs=${nixpkgsSrc}"
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
      # nix-path covers env-scrubbed non-login contexts (e.g. `ssh host cmd`).
      "nix/nix.conf".text = ''
        experimental-features = nix-command flakes
        build-users-group = nixbld
        trusted-users = root exedev hermes
        substituters = https://cache.nixos.org/
        trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
        sandbox = false
        nix-path = nixpkgs=${nixpkgsSrc}
      '';
      # pins nixpkgs flake refs to the image's rev — the nixos-25.11 pin is
      # fully covered by cache.nixos.org, unlike the registry default
      # (unstable), which rotates out of cache and rebuilds from source.
      "nix/registry.json".text = builtins.toJSON {
        version = 2;
        flakes = [
          {
            exact = true;
            from = {
              type = "indirect";
              id = "nixpkgs";
            };
            to = {
              type = "path";
              path = "${nixpkgsSrc}";
            };
          }
        ];
      };
      # sshd resets the env, so login shells re-source this via /etc/profile.
      "profile.d/nix.sh".text = ''
        export PATH="$HOME/.nix-profile/bin:${profile}/bin:${profile}/sbin:$PATH"
        export NIX_REMOTE=daemon
        export NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
        export NIX_PATH="nixpkgs=${nixpkgsSrc}"
        # nix-env -iA nixpkgs.* reads ~/.nix-defexpr, not NIX_PATH.
        if [ ! -e "$HOME/.nix-defexpr/nixpkgs" ]; then
          mkdir -p "$HOME/.nix-defexpr" && ln -sfn ${nixpkgsSrc} "$HOME/.nix-defexpr/nixpkgs"
        fi
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
      # must use the local store; inheriting NIX_REMOTE=daemon (image.env) makes
      # it connect to its own socket and fork-bomb the store until PIDs exhaust.
      run = "NIX_REMOTE= exec ${pkgs.nix}/bin/nix-daemon --daemon";
    };
  };
}
