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

  # The real state (webui.db, uploads, vector store, secret key) lives under
  # DATA_DIR in the state dir, which is backed up. The embedding-model caches
  # (HF_HOME / sentence-transformers, ~900M, re-downloaded on demand) go under
  # the cache dir instead, so backups stay lean and hold only real data.
  environment = {
    DATA_DIR = "${cfg.stateDir}/data";
    STATIC_DIR = "${cfg.stateDir}/static";
    HF_HOME = "${cfg.cacheDir}/hf";
    SENTENCE_TRANSFORMERS_HOME = "${cfg.cacheDir}/sentence-transformers";
    # no phone-home.
    ANONYMIZED_TELEMETRY = "False";
    DO_NOT_TRACK = "True";
    SCARF_NO_ANALYTICS = "True";
  }
  // cfg.environment;

  envArgs = lib.concatStringsSep " \\\n          " (
    lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg v}") (user.environment // environment)
  );
in
{
  options.services.open-webui = {
    enable = lib.mkEnableOption "Open WebUI (a self-hosted LLM chat frontend), supervised by s6";
    package = mkOption {
      type = types.package;
      default = pkgs.open-webui;
      defaultText = lib.literalExpression "pkgs.open-webui";
      description = "Open WebUI package (must expose bin/open-webui).";
    };
    user = mkOption {
      type = types.str;
      default = "open-webui";
      description = "Account to run Open WebUI as; declared by this module.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/open-webui";
      description = "State directory (DATA_DIR lives under it); also the account's home. Back this up.";
    };
    cacheDir = mkOption {
      type = types.str;
      default = "/var/cache/open-webui";
      description = "Regeneratable model caches (HF_HOME, sentence-transformers); kept out of the state dir so it needn't be backed up.";
    };
    port = mkOption {
      type = types.port;
      default = 9999;
      description = "Public port Open WebUI binds and the image exposes.";
    };
    ports = mkOption {
      type = types.listOf types.port;
      default = [ ];
      description = "Additional public ports to expose.";
    };
    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Extra environment for the open-webui process; wins over the module
        defaults. See https://docs.openwebui.com/getting-started/env-configuration.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      uid = 2000;
      group = cfg.user;
      home = cfg.stateDir;
      createHome = true;
      shell = "/bin/sh";
      description = "Open WebUI";
    };
    users.groups.${cfg.user}.gid = 2000;

    s6.services.open-webui-setup = {
      type = "oneshot";
      dependencies = [
        "base"
      ]
      ++ lib.optional config.services.backup.enable "backup-restore";
      run = ''
        mkdir -p ${environment.DATA_DIR} ${cfg.cacheDir}
        chown -R ${toString user.uid}:${gid} ${cfg.stateDir} ${cfg.cacheDir}
      '';
    };

    # Open WebUI handles Host/Origin and websockets itself, so it binds the
    # public port directly (no caddy shim); exe.dev's auth gates it (see the
    # install-shelley label below).
    s6.services.open-webui = {
      dependencies = [
        "base"
        "open-webui-setup"
      ];
      run = ''
        # open-webui writes .webui_secret_key relative to CWD; s6's servicedir
        # CWD is read-only, so run from the writable (backed-up) state dir.
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
          ${cfg.package}/bin/open-webui serve --host 0.0.0.0 --port ${toString cfg.port}
      '';
    };

    image.packages = [ cfg.package ];
    image.exposedPorts.tcp = [ cfg.port ] ++ cfg.ports;
    image.labels."exe.dev/install-shelley" = "true";
  };
}
