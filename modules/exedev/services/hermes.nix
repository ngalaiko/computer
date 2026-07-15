{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.services.hermes;
  user = config.users.users.${cfg.user};
  gid = toString config.users.groups.${user.group}.gid;
  settingsFormat = pkgs.formats.yaml { };
  hermesHome = "${user.home}/.hermes";
  configFile = settingsFormat.generate "hermes-config.yaml" cfg.settings;

  runAsHermes =
    args:
    ''
      exec /command/s6-setuidgid ${cfg.user} \
        env \
          HOME=${user.home} \
          USER=${cfg.user} \
          SHELL=/bin/sh \
          PATH=${user.home}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/bin:/sbin:/usr/bin \
          NIX_REMOTE=daemon \
          SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
          NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
          ${
            lib.concatStringsSep " \\\n          " (
              lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg v}") cfg.environment
            )
          } \
    ''
    + args;
in
{
  options.services.hermes = {
    enable = lib.mkEnableOption "the Hermes agent (dashboard + messaging gateway), supervised by s6";
    package = mkOption {
      type = types.package;
      description = "Hermes package (must expose bin/hermes).";
    };
    user = mkOption {
      type = types.str;
      default = "hermes";
      description = "Account to run Hermes as; declared by this module.";
    };
    ports = mkOption {
      type = types.listOf types.port;
      default = [ 9999 ];
      description = "Public ports to expose; the first is used for the dashboard proxy.";
    };
    internalPort = mkOption {
      type = types.listOf types.port;
      default = 9119;
      description = "Loopback port hermes itself binds.";
    };
    settings = mkOption {
      type = settingsFormat.type;
      default = { };
      description = "Seed config.yaml, written only on first boot when none exists (backup/edits win after).";
    };
    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment for the hermes processes.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      uid = 2000;
      group = cfg.user;
      home = "/var/lib/hermes";
      createHome = true;
      shell = "/bin/sh";
      description = "Hermes agent";
    };
    users.groups.${cfg.user}.gid = 2000;

    s6.services.hermes-setup = {
      type = "oneshot";
      dependencies = [
        "base"
      ]
      ++ lib.optional config.services.backup.enable "backup-restore";
      # seed config.yaml only when absent; a restored or hand-edited one wins.
      run = ''
        mkdir -p ${hermesHome}
        [ -e ${hermesHome}/config.yaml ] || cp ${configFile} ${hermesHome}/config.yaml
        chown -R ${toString user.uid}:${gid} ${hermesHome}
      '';
    };

    s6.services.hermes = {
      dependencies = [
        "base"
        "hermes-setup"
      ];
      run = runAsHermes ''
        ${cfg.package}/bin/hermes dashboard \
          --host 127.0.0.1 --port ${toString cfg.internalPort} --no-open
      '';
    };

    # caddy binds the public port and rewrites Host+Origin to the loopback
    # upstream; hermes's loopback Host/Origin guards 400 the proxied request
    # (and reject the wss upgrade) otherwise.
    s6.services.hermes-proxy = {
      dependencies = [
        "base"
        "hermes-setup"
      ];
      run = ''
        mkdir -p /run/caddy
        chown ${toString user.uid}:${gid} /run/caddy
        exec /command/s6-setuidgid ${cfg.user} \
          env HOME=${user.home} XDG_DATA_HOME=/run/caddy XDG_CONFIG_HOME=/run/caddy \
          ${pkgs.caddy}/bin/caddy reverse-proxy \
            --from http://:${toString (builtins.head cfg.ports)} \
            --to 127.0.0.1:${toString cfg.internalPort} \
            --change-host-header \
            --header-up "Origin: http://127.0.0.1:${toString cfg.internalPort}"
      '';
    };

    s6.services.hermes-gateway = {
      dependencies = [
        "base"
        "hermes-setup"
      ]
      ++ lib.optional config.services.backup.enable "backup-restore";
      run = runAsHermes ''
        ${cfg.package}/bin/hermes gateway run
      '';
    };

    image.packages = [ cfg.package ];
    image.exposedPorts.tcp = cfg.ports;
    image.labels."exe.dev/install-shelley" = "true";
  };
}
