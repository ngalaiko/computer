{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.services.open-webui;
  user = config.users.users.${cfg.user};
  gid = toString config.users.groups.${user.group}.gid;

  envArgs = lib.concatStringsSep " \\\n          " (
    lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg v}") (user.environment // cfg.environment)
  );
in
{
  options.services.open-webui = {
    enable = lib.mkEnableOption "Open WebUI (self-hosted LLM chat frontend), supervised by s6";
    package = mkOption {
      type = types.package;
      description = "open-webui package (must expose bin/open-webui).";
    };
    user = mkOption {
      type = types.str;
      default = "open-webui";
      description = "Non-root account open-webui runs as. Declared here.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/open-webui";
      description = "Home + state (accounts db, uploads, vector db, secret key, model caches); also the account's home. Back this up.";
    };
    port = mkOption {
      type = types.port;
      default = 8081;
      description = "Loopback port open-webui listens on. Deliberately not an image-exposed port: tailscale serve proxies the tailnet Service to it over localhost, so it never needs to leave the box.";
    };
    environment = mkOption {
      type = types.attrsOf types.str;
      default = {
        SCARF_NO_ANALYTICS = "true";
        DO_NOT_TRACK = "true";
        ANONYMIZED_TELEMETRY = "false";
      };
      description = "Extra environment for the open-webui process; wins over the account's environment.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      uid = 2001;
      group = cfg.user;
      home = cfg.stateDir;
      createHome = true;
      shell = "/bin/sh";
      description = "Open WebUI";
    };
    users.groups.${cfg.user}.gid = 2001;

    s6.services.open-webui-setup = {
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

    # Runs unprivileged as ${cfg.user}, bound to loopback only — the tailnet
    # Service (tailscale serve) is the sole way in, and tailscaled proxies to
    # localhost from this box. All state is rooted under ${cfg.stateDir}: the
    # data dir (webui.db, uploads, vector db), the generated static assets, and
    # the HF/sentence-transformers model caches (churny, but simpler to keep the
    # whole dir in one backup set). The cwd matters: open-webui drops its
    # .webui_secret_key (JWT signing key) in $PWD, and losing it logs everyone
    # out.
    s6.services.open-webui = {
      dependencies = [
        "base"
        "open-webui-setup"
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
            DATA_DIR=${cfg.stateDir}/data \
            STATIC_DIR=${cfg.stateDir}/static \
            HF_HOME=${cfg.stateDir}/cache/hf \
            SENTENCE_TRANSFORMERS_HOME=${cfg.stateDir}/cache/sentence-transformers \
            ${envArgs} \
          ${cfg.package}/bin/open-webui serve --host 127.0.0.1 --port ${toString cfg.port}
      '';
    };

    image.packages = [ cfg.package ];
  };
}
