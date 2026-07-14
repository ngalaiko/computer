# Hermes (Nous Research's coding agent) under s6, running as its own account:
#
#  - hermes-setup   (oneshot) seeds the nix-managed config.yaml + owns the
#                   state dir; the two long-runs depend on it.
#  - hermes         (longrun) the web dashboard (chat UI + API).
#  - hermes-proxy   (longrun) caddy bridging 0.0.0.0:<port> to the dashboard.
#  - hermes-gateway (longrun) the messaging gateway (Telegram etc). Dormant
#                   until its token env var is present, so it ships ready but
#                   idle — set the token (e.g. exe.dev new --env
#                   TELEGRAM_BOT_TOKEN=…) and it connects on next boot.
#
# No dashboard auth: exe.dev's HTTPS proxy authenticates in front. Hermes
# hard-requires an auth provider on any non-loopback bind (June 2026
# hardening, no opt-out) but treats loopback as trusted — so hermes binds
# 127.0.0.1:<internalPort> and caddy bridges the public port to it. caddy
# rewrites two headers so hermes's loopback guards accept the proxied request:
#   - Host  → the loopback upstream (else the HTTP Host guard 400s).
#   - Origin → the loopback upstream. Hermes's WebSocket guard rejects an
#     Origin whose host isn't the bound (loopback) one, so without this the
#     browser's https://<vm>.exe.xyz Origin fails the chat + PTY wss upgrades
#     ("origin_mismatch"). The DNS-rebinding defence this guards is moot here
#     since caddy is the only client and exe.dev's proxy fronts it.
#
# LLM access goes through exe.dev's metadata gateway, configured as named
# providers in settings.providers; the gateway authenticates the VM, so each
# api_key is a placeholder.
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

  # `env <overrides> cmd` keeps the inherited (with-contenv) environment and
  # adds ours on top, so tokens from the container env pass through to hermes.
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
    # nixpkgs has no hermes-agent; the flake wires in the package from the
    # hermes-agent input (it builds itself with uv2nix against its own pin).
    package = mkOption {
      type = types.package;
      description = "Hermes package (must expose bin/hermes).";
    };
    user = mkOption {
      type = types.str;
      default = "hermes";
      description = "Account to run Hermes as; declared by this module.";
    };
    port = mkOption {
      type = types.port;
      default = 9999;
      description = "Public port caddy serves the dashboard on.";
    };
    internalPort = mkOption {
      type = types.port;
      default = 9119;
      description = "Loopback port hermes itself binds (auth-exempt).";
    };
    gateway.tokenEnv = mkOption {
      type = types.str;
      default = "TELEGRAM_BOT_TOKEN";
      description = "Env var whose presence activates the messaging gateway (and, for Telegram, the bot token hermes reads directly).";
    };
    settings = mkOption {
      type = settingsFormat.type;
      default = { };
      description = "Hermes config.yaml contents (nix-managed: rewritten on every boot).";
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

    # Shared state setup, once, before the long-runs (runs as root).
    s6.services.hermes-setup = {
      type = "oneshot";
      run = ''
        mkdir -p ${hermesHome}
        cp ${configFile} ${hermesHome}/config.yaml
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
            --from http://:${toString cfg.port} \
            --to 127.0.0.1:${toString cfg.internalPort} \
            --change-host-header \
            --header-up "Origin: http://127.0.0.1:${toString cfg.internalPort}"
      '';
    };

    s6.services.hermes-gateway = {
      dependencies = [
        "base"
        "hermes-setup"
      ];
      # Idle (supervised, no restart loop) until the token env var appears, so
      # the service ships ready but dormant. with-contenv has populated the
      # container env by the time this runs.
      run = ''
        if [ -z "$(printenv ${cfg.gateway.tokenEnv} 2>/dev/null || true)" ]; then
          echo "hermes-gateway: ${cfg.gateway.tokenEnv} unset — idling; set it and restart to enable messaging." >&2
          exec ${pkgs.coreutils}/bin/sleep infinity
        fi
      ''
      + runAsHermes ''
        ${cfg.package}/bin/hermes gateway run
      '';
    };

    image.packages = [ cfg.package ];
    image.exposedPorts.tcp = [ cfg.port ];
    # read by exe.dev at VM creation (keeps the platform's agent UI wiring)
    image.labels."exe.dev/install-shelley" = "true";
  };
}
