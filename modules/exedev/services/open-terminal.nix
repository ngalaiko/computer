{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.services.open-terminal;
  user = config.users.users.${cfg.user};
  gid = toString config.users.groups.${user.group}.gid;
  keyFile = "${cfg.stateDir}/api-key";

  envArgs = lib.concatStringsSep " \\\n          " (
    lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg v}") (user.environment // cfg.environment)
  );
in
{
  options.services.open-terminal = {
    enable = lib.mkEnableOption "Open Terminal (REST-API shell for AI agents), supervised by s6";
    package = mkOption {
      type = types.package;
      description = "open-terminal package (must expose bin/open-terminal).";
    };
    user = mkOption {
      type = types.str;
      default = "open-terminal";
      description = "Non-root account open-terminal runs as; every command an agent sends executes with this account's permissions, so it is the security boundary. Declared here.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/open-terminal";
      description = "Home + workspace (the files agents create/edit) and the generated API key; also the account's home. Back this up.";
    };
    port = mkOption {
      type = types.port;
      default = 8000;
      description = "Loopback port open-terminal listens on. Deliberately not an image-exposed port and not on the tailnet: only the co-located open-webui talks to it, over localhost.";
    };
    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment for the open-terminal process; wins over the account's environment.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      uid = 2002;
      group = cfg.user;
      home = cfg.stateDir;
      createHome = true;
      shell = "/bin/sh";
      description = "Open Terminal";
    };
    users.groups.${cfg.user}.gid = 2002;

    # Also mints the API key once (0600, owned by the account) so it survives
    # restarts — the app would otherwise generate a fresh one per boot and
    # break the paired open-webui config. Read it from ${keyFile} to paste
    # into open-webui.
    s6.services.open-terminal-setup = {
      type = "oneshot";
      dependencies = [
        "base"
      ]
      ++ lib.optional config.services.backup.enable "backup-restore";
      run = ''
        mkdir -p ${cfg.stateDir}
        if [ ! -s ${keyFile} ]; then
          umask 077
          od -An -tx1 -N32 /dev/urandom | tr -d ' \n' > ${keyFile}
        fi
        chown -R ${toString user.uid}:${gid} ${cfg.stateDir}
        chmod 0600 ${keyFile}
      '';
    };

    # Runs unprivileged as ${cfg.user}, bound to loopback only. The key goes in
    # via the environment (the documented OPEN_TERMINAL_API_KEY), never argv —
    # argv is world-readable through ps. Commands agents send run with this
    # account's permissions (no sudo, not nix-trusted), which caps what a
    # connected model can do on the box.
    s6.services.open-terminal = {
      dependencies = [
        "base"
        "open-terminal-setup"
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
            OPEN_TERMINAL_API_KEY="$(cat ${keyFile})" \
            ${envArgs} \
          ${cfg.package}/bin/open-terminal run --host 127.0.0.1 --port ${toString cfg.port}
      '';
    };

    image.packages = [ cfg.package ];
  };
}
