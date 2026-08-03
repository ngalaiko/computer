{ pkgs, ... }:
let
  # pi (the coding agent) is an npm CLI, packaged from its published tarball.
  # MIT, all-JS deps, so it builds against the pinned nixpkgs directly (no
  # unstable / allowUnfree, unlike cptr).
  pi = import ../../../packages/pi { inherit pkgs; };
in
{
  users.users.assistant = {
    uid = 2001;
    group = "assistant";
    home = "/var/lib/assistant";
    createHome = true;
    shell = "/bin/sh";
    description = "Assistant (pi coding agent)";

    # pi plus the tools it drives (git, gh, ripgrep, …) and a node runtime for
    # its TypeScript extensions / any node subprocesses. The account is
    # unprivileged (no sudo, not nix-trusted), which caps what the agent can do
    # on the box; BYOK provider keys are supplied at runtime, not baked in.
    packages = with pkgs; [
      pi
      nodejs_22
      git
      gh
      jq
      ripgrep
      curl
      coreutils
      uv
    ];
  };
  users.groups.assistant.gid = 2001;

  services.backup = {
    enable = true;
    # pi's config, auth (provider keys), session history, and the agent
    # workspace all live under the home. This also covers the runtime-installed
    # pi plugins (~/.pi/agent/npm) and the pi-gateway state below
    # (~/.pi/gateway: config.json with the bot token, gateway-sessions.db), so a
    # recreated machine restores them.
    paths = [ "/var/lib/assistant" ];
  };

  # Telegram bridge for pi, via the @gamalan/pi-gateway plugin. The plugin is
  # installed at runtime (`pi install npm:@gamalan/pi-gateway` as assistant) into
  # ~/.pi/agent/npm and restored from backup on a fresh machine; this service
  # keeps its daemon supervised so the bot is reachable again after any reboot or
  # recreation. Long-polling (no webhookUrl in ~/.pi/gateway/config.json) needs
  # only outbound HTTPS, so nothing is exposed on the tailnet or the image.
  s6.services.assistant-gateway = {
    dependencies = [
      "base"
      # wait for the restore so ~/.pi (the installed plugin + config) is present.
      "backup-restore"
    ];
    run = ''
      # `pi-gateway start` always double-forks a detached daemon, which s6 can't
      # supervise; run the daemon entry it spawns (dist/index.js --daemon) in the
      # foreground instead. Locate it by glob so we don't hard-code npm's global
      # layout. Until the plugin is installed (first-ever boot, empty backup),
      # pace the restart loop instead of hammering.
      entry=$(${pkgs.findutils}/bin/find /var/lib/assistant/.pi/agent/npm \
        -path '*/@gamalan/pi-gateway/dist/index.js' 2>/dev/null \
        | ${pkgs.coreutils}/bin/head -n1)
      if [ -z "$entry" ]; then
        echo "pi-gateway not installed under /var/lib/assistant/.pi/agent/npm;" \
             "run 'pi install npm:@gamalan/pi-gateway' as assistant. Retrying in 60s."
        ${pkgs.coreutils}/bin/sleep 60
        exit 1
      fi
      exec /command/s6-setuidgid assistant \
        env \
          HOME=/var/lib/assistant \
          USER=assistant \
          SHELL=/bin/sh \
          PATH=/var/lib/assistant/.pi/agent/npm/bin:/var/lib/assistant/.nix-profile/bin:/etc/profiles/per-user/assistant/bin:/nix/var/nix/profiles/default/bin:/bin:/sbin:/usr/bin \
          SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
          NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
        ${pkgs.nodejs_22}/bin/node "$entry" --daemon
    '';
  };
}
