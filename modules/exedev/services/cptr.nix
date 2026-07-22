{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.services.cptr;
  user = config.users.users.${cfg.user};
  gid = toString config.users.groups.${user.group}.gid;

  envArgs = lib.concatStringsSep " \\\n          " (
    lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg v}") (user.environment // cfg.environment)
  );
in
{
  options.services.cptr = {
    enable = lib.mkEnableOption "Open WebUI Computer (cptr): the machine in a browser, supervised by s6";
    package = mkOption {
      type = types.package;
      description = "cptr package (must expose bin/cptr).";
    };
    user = mkOption {
      type = types.str;
      default = "cptr";
      description = "Non-root account cptr runs as; it serves this account's shell, files, and git. Declared here.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/cptr";
      description = "Home + state (the admin account, its db, and workspaces live here); also the account's home. Back this up.";
    };
    port = mkOption {
      type = types.port;
      default = 9999;
      description = "Public port cptr binds and the image exposes.";
    };
    ports = mkOption {
      type = types.listOf types.port;
      default = [ ];
      description = "Additional public ports to expose.";
    };
    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment for the cptr process; wins over the account's environment.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      uid = 2000;
      group = cfg.user;
      home = cfg.stateDir;
      createHome = true;
      shell = "/bin/sh";
      description = "Open WebUI Computer (cptr)";
    };
    users.groups.${cfg.user}.gid = 2000;

    s6.services.cptr-setup = {
      type = "oneshot";
      dependencies = [
        "base"
      ]
      ++ lib.optional config.services.backup.enable "backup-restore";
      run = ''
        mkdir -p ${cfg.stateDir}
        chown -R ${toString user.uid}:${gid} ${cfg.stateDir}
      '';
    };

    # Runs unprivileged as ${cfg.user}: cptr serves that account's shell/files.
    # --headless prints the one-time setup URL (with token) to the log instead
    # of opening a browser; grab it from /var/log/cptr/current on first boot to
    # create the admin account. exe.dev auth gates the port (install-shelley).
    s6.services.cptr = {
      dependencies = [
        "base"
        "cptr-setup"
      ];
      run = ''
        cd ${cfg.stateDir}
        exec /command/s6-setuidgid ${cfg.user} \
          env \
            HOME=${cfg.stateDir} \
            USER=${cfg.user} \
            SHELL=/bin/sh \
            PATH=${cfg.stateDir}/.nix-profile/bin:/etc/profiles/per-user/${cfg.user}/bin:/nix/var/nix/profiles/default/bin:/bin:/sbin:/usr/bin \
            SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
            NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
            ${envArgs} \
          ${cfg.package}/bin/cptr run --headless --host 0.0.0.0 --port ${toString cfg.port}
      '';
    };

    image.packages = [ cfg.package ];
    image.exposedPorts.tcp = [ cfg.port ] ++ cfg.ports;
    image.labels."exe.dev/install-shelley" = "true";
  };
}
