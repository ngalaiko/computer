# Nix in the image: a multi-user daemon over a registered store, so the agent
# (and ssh users) can `nix profile install nixpkgs#…` or build at runtime.
#
# The store is root-owned (baked by the image build), so installs must go
# through a root daemon — hence the daemon + nixbld build users + NIX_REMOTE.
# The store db is empty in a from-scratch image, so a first-boot oneshot loads
# it from a build-time closure manifest (closureInfo). That manifest is scoped
# to image.packages and never image.rootPaths: the loader is an s6 service, so
# it lives under rootPaths, and feeding rootPaths back into the closure would
# be an eval cycle. A handful of thin generated scripts stay unregistered as a
# result — fine for install/build, just don't `nix-collect-garbage` the world.
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

    # nix-aware container env (overrides core's default): daemon client + the
    # default profile on PATH + cert vars for substituter/flake fetches.
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
      # login shells (ssh): the container env already carries these, but sshd
      # resets it, so /etc/profile sources this.
      "profile.d/nix.sh".text = ''
        export PATH="$HOME/.nix-profile/bin:${profile}/bin:${profile}/sbin:$PATH"
        export NIX_REMOTE=daemon
        export NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
      '';
    };

    # Load the baked store into the db once, before the daemon serves clients.
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
