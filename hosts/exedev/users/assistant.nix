{ pkgs, inputs, ... }:
let
  # pi (the coding agent) is an npm CLI, packaged from its published tarball.
  # MIT, all-JS deps, so it builds against the pinned nixpkgs directly.
  pi = import ../../../packages/pi { inherit pkgs; };
  # pilegram: my pi ⇄ Telegram gateway (Bun), consumed as a flake input. It's a
  # hermetic package — it bundles bun, ffmpeg, whisper.cpp and a pinned
  # node_modules that includes its own pi 0.83.0 — so it needs nothing else from
  # this account and survives recreations regardless of backup.
  pilegram = inputs.pilegram.packages.${pkgs.system}.default;
  # Official Obsidian Sync headless CLI, packaged here so the assistant can run
  # on-demand vault syncs without fetching npm packages at runtime.
  obsidian-headless = import ../../../packages/obsidian-headless { inherit pkgs; };
  obsidian-sync = pkgs.writeShellScriptBin "obsidian-sync" ''
    set -eu
    vault="''${OBSIDIAN_VAULT_DIR:-/var/lib/assistant/Vault}"
    exec ${obsidian-headless}/bin/ob sync --path "$vault" "$@"
  '';
in
{
  users.users.assistant = {
    uid = 2001;
    group = "assistant";
    home = "/var/lib/assistant";
    createHome = true;
    shell = "/bin/sh";
    description = "Assistant (pi coding agent)";

    # pi plus the tools it drives (git, gh, ripgrep, Chromium, …) and a node
    # runtime for its TypeScript extensions / any node subprocesses. The account is
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
      fd # pi checks for fd at interactive startup and uses it for file autocomplete/find.
      ledger
      chromium
      obsidian-headless
      obsidian-sync
    ];
  };
  users.groups.assistant.gid = 2001;

  # /assistant/* on the public port. The ingress module also puts caddy on the
  # assistant PATH so the agent can validate and reload ~/.caddy/Caddyfile.
  services.ingress.tenants.assistant = {
    upstreamPort = 8083;
  };

  services.backup = {
    enable = true;
    # pi's config, auth (provider keys), session history, and the agent
    # workspace all live under the home. This also covers the runtime-installed
    # pi plugins (~/.pi/agent/npm) and pilegram's state (~/.config/pilegram: its
    # SQLite db + per-topic workspaces, and the runtime env file holding the bot
    # token + allow-list), so a recreated machine restores them. pilegram's
    # ~2 GB speech-model cache (~/.cache/pilegram) is re-downloadable and is
    # already skipped by the base `.cache` exclude.
    paths = [
      "/var/lib/assistant"
    ];
  };

  # Telegram bridge for pi, via pilegram (the flake input above). Long-polling
  # needs only outbound HTTPS, so nothing is exposed on the tailnet or the image.
  # pilegram reads pi's provider keys from ~/.pi and keeps its own state under
  # ~/.config/pilegram; run in the foreground so s6 supervises it.
  s6.services.assistant-gateway = {
    dependencies = [
      "base"
      # wait for the restore so ~/.config/pilegram (state + the env file) is present.
      "backup-restore"
    ];
    run = ''
      # The bot token and allow-list stay out of this (public) repo and the Nix
      # store: they live in a runtime env file under the backed-up home, placed
      # once on a fresh machine and restored thereafter (see README). The token
      # is exported into the environment, never passed as a flag — argv is
      # visible in `ps`; the allow-list (non-secret Telegram user ids) is a flag.
      envfile=/var/lib/assistant/.config/pilegram/env
      if [ ! -f "$envfile" ]; then
        echo "assistant-gateway: $envfile missing; place TELEGRAM_BOT_TOKEN + PILEGRAM_ALLOW (see README). Retrying." >&2
        sleep 10
        exit 1
      fi
      set -a
      . "$envfile"
      set +a
      if [ -z "''${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "''${PILEGRAM_ALLOW:-}" ]; then
        echo "assistant-gateway: TELEGRAM_BOT_TOKEN or PILEGRAM_ALLOW unset in $envfile. Retrying." >&2
        sleep 10
        exit 1
      fi
      # TELEGRAM_BOT_TOKEN is already exported (set -a above); `env` (no -i) and
      # s6-setuidgid both preserve it, so it reaches pilegram without ever
      # appearing in argv. NODE_EXTRA_CA_CERTS points bun at the system CA bundle
      # for outbound HTTPS (Telegram, Hugging Face model downloads).
      exec /command/s6-setuidgid assistant \
        env \
          HOME=/var/lib/assistant \
          USER=assistant \
          SHELL=/bin/sh \
          PATH=/etc/profiles/per-user/assistant/bin:/nix/var/nix/profiles/default/bin:/bin:/sbin:/usr/bin \
          SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
          NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
          NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-bundle.crt \
        ${pilegram}/bin/pilegram \
          --allow "$PILEGRAM_ALLOW" \
          --state-dir /var/lib/assistant/.config/pilegram \
          --models-dir /var/lib/assistant/.cache/pilegram
    '';
  };
}
