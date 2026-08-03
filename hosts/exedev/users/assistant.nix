{ pkgs, ... }:
let
  # pi (the coding agent) is an npm CLI, packaged from its published tarball.
  # MIT, all-JS deps, so it builds against the pinned nixpkgs directly (no
  # unstable / allowUnfree, unlike cptr).
  pi = import ../../../packages/pi { inherit pkgs; };
  # the pi-gateway plugin, self-contained (peers + native better-sqlite3 bundled).
  piGateway = import ../../../packages/pi-gateway { inherit pkgs; };
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

  # Telegram bridge for pi, via the @gamalan/pi-gateway plugin — Nix-packaged
  # with its peer deps and native better-sqlite3 in packages/pi-gateway, so it's
  # always in the image (no runtime `pi install`, survives recreations
  # regardless of backup). Its config + session dbs live in ~/.pi/gateway (backed
  # up, and not under a node_modules). Long-polling (no webhookUrl in
  # ~/.pi/gateway/config.json) needs only outbound HTTPS, so nothing is exposed
  # on the tailnet or the image.
  s6.services.assistant-gateway = {
    dependencies = [
      "base"
      # wait for the restore so ~/.pi/gateway (config + sessions) is present.
      "backup-restore"
    ];
    run = ''
      # Run the daemon (what `pi-gateway start` otherwise double-forks) in the
      # foreground so s6 supervises it. pi (for the `pi --mode rpc` the gateway
      # spawns per chat) is on the account PATH.
      exec /command/s6-setuidgid assistant \
        env \
          HOME=/var/lib/assistant \
          USER=assistant \
          SHELL=/bin/sh \
          PATH=/etc/profiles/per-user/assistant/bin:/nix/var/nix/profiles/default/bin:/bin:/sbin:/usr/bin \
          SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
          NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
        ${piGateway}/bin/pi-gateway-daemon --daemon
    '';
  };
}
