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
  # wherenow: the "Where Now?" location backend (flake input). Pure Go; writes
  # positions into the vault as notes (no database).
  wherenow = inputs.wherenow.packages.${pkgs.system}.default;
  # Official Obsidian Sync headless CLI, packaged here so the assistant can run
  # on-demand vault syncs without fetching npm packages at runtime.
  obsidian-headless = import ../../../packages/obsidian-headless { inherit pkgs; };
  obsidian-sync = pkgs.writeShellScriptBin "obsidian-sync" ''
    set -eu
    vault="''${OBSIDIAN_VAULT_DIR:-/var/lib/assistant/Vault}"
    exec ${obsidian-headless}/bin/ob sync --path "$vault" "$@"
  '';
  # vault-sync: stdlib-only Python that writes Letterboxd watches into Movie
  # notes and the Discogs collection+wantlist into Album notes. Additive only —
  # it dedups on each note's letterboxd:/discogs: URL, so it appends a new
  # watched date or fills a blank lp:, never rewriting a hand-curated note.
  vault-sync = import ../../../packages/vault-sync { inherit pkgs; };
  # Letterboxd is public (hourly); Discogs is rate-limited and rarely changes
  # (every 6h). Discogs self-skips without a token, so a missing token never
  # blocks the Letterboxd half.
  vaultSyncCrontab = pkgs.writeText "vault-sync-crontab" ''
    17 * * * * ${vault-sync}/bin/vault-sync-letterboxd
    47 */6 * * * ${vault-sync}/bin/vault-sync-discogs
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
      himalaya # CLI for the assistant's authorized iCloud Mail access.
      chromium
      obsidian-headless
      obsidian-sync
      vault-sync # `vault-sync-letterboxd` / `vault-sync-discogs`, for manual runs
    ];
  };
  users.groups.assistant.gid = 2001;

  # /assistant/* on the public port, served by the assistant's own caddy (the
  # ingress module also puts caddy on the assistant PATH so the agent can
  # validate and reload ~/.caddy/Caddyfile). It fronts wherenow at
  # /assistant/wherenow/* -> the wherenow backend on loopback 8085: the root
  # caddy strips /assistant, this handle strips /wherenow, so wherenow sees
  # /api/*. The trailing 404 leaves the rest of /assistant/* the agent's to
  # self-manage. Public, but every wherenow write needs the bearer TOKEN.
  #
  # NB: `routes` is only the SEED for the tenant's Caddyfile. A box that already
  # has ~assistant/.caddy/Caddyfile keeps its copy, so on first rollout add this
  # handle there by hand (or delete the file to let it re-seed) then reload caddy.
  services.ingress.tenants.assistant = {
    upstreamPort = 8083;
    routes = ''
      handle_path /wherenow/* {
        reverse_proxy 127.0.0.1:8085
      }
      respond "assistant: no routes configured yet" 404
    '';
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

  # Keep the assistant's Obsidian vault connected to Obsidian Sync. The auth,
  # sync setup, and vault data are runtime state under the backed-up assistant
  # home; this service only starts once backup restore has completed.
  s6.services.assistant-obsidian-sync = {
    dependencies = [
      "base"
      "backup-restore"
    ];
    run = ''
      vault=/var/lib/assistant/Vault
      if [ ! -d "$vault/.obsidian" ]; then
        echo "assistant-obsidian-sync: $vault is not configured yet; run ob login + ob sync-setup once. Retrying." >&2
        sleep 30
        exit 1
      fi
      exec /command/s6-setuidgid assistant \
        env \
          HOME=/var/lib/assistant \
          USER=assistant \
          SHELL=/bin/sh \
          PATH=/etc/profiles/per-user/assistant/bin:/nix/var/nix/profiles/default/bin:/bin:/sbin:/usr/bin \
          SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
          NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
          NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-bundle.crt \
        ${obsidian-headless}/bin/ob sync --path "$vault" --continuous
    '';
  };

  # wherenow: the "Where Now?" iOS app POSTs positions here and wherenow writes
  # each one straight into the vault as a note (no database), so daily notes show
  # where I've been. Runs as the assistant so it can write the vault; listens on
  # loopback 8085 (the assistant's own ingress caddy fronts it at
  # /assistant/wherenow/*). The bearer TOKEN lives in a runtime env file, placed
  # once on a fresh machine (see README) and exported into the environment so it
  # never appears in argv. tzdata is embedded in the binary, so --tz resolves
  # without system zoneinfo.
  s6.services.assistant-wherenow = {
    dependencies = [
      "base"
      "backup-restore"
    ];
    run = ''
      vault=/var/lib/assistant/Vault
      if [ ! -d "$vault/.obsidian" ]; then
        echo "assistant-wherenow: $vault not configured yet (run ob sync-setup). Retrying." >&2
        sleep 30
        exit 1
      fi
      envfile=/var/lib/assistant/.config/wherenow/env
      if [ ! -f "$envfile" ]; then
        echo "assistant-wherenow: $envfile missing; place TOKEN=... (see README). Retrying." >&2
        sleep 10
        exit 1
      fi
      set -a
      . "$envfile"
      set +a
      if [ -z "''${TOKEN:-}" ]; then
        echo "assistant-wherenow: TOKEN unset in $envfile. Retrying." >&2
        sleep 10
        exit 1
      fi
      # TOKEN is exported (set -a), so `env` (no -i) and s6-setuidgid pass it
      # through the environment; it never appears in argv (which `ps` can see).
      exec /command/s6-setuidgid assistant \
        env \
          HOME=/var/lib/assistant \
          USER=assistant \
          SHELL=/bin/sh \
          PATH=/etc/profiles/per-user/assistant/bin:/nix/var/nix/profiles/default/bin:/bin:/sbin:/usr/bin \
          PORT=8085 \
        ${wherenow}/bin/wherenow \
          --vault-dir="$vault" \
          --tz=Europe/Stockholm
    '';
  };

  # vault-sync: supercronic runs the Letterboxd (Movies) and Discogs (Albums)
  # polls on a schedule, as the assistant so the notes are written into the
  # vault it owns; obsidian-sync then propagates them. Guards on the vault being
  # set up, like the services above.
  s6.services.assistant-vault-sync = {
    dependencies = [
      "base"
      "backup-restore"
    ];
    run = ''
      vault=/var/lib/assistant/Vault
      if [ ! -d "$vault/.obsidian" ]; then
        echo "assistant-vault-sync: $vault not configured yet (run ob sync-setup). Retrying." >&2
        sleep 30
        exit 1
      fi
      # Optional runtime env: DISCOGS_TOKEN (+ optional LETTERBOXD_USERNAME /
      # DISCOGS_USERNAME). Absent -> the Discogs poll self-skips and only
      # Letterboxd (public) runs. Exported (set -a) so `env` (no -i) and
      # s6-setuidgid pass it to supercronic's jobs through the environment,
      # never argv.
      envfile=/var/lib/assistant/.config/vault-sync/env
      if [ -f "$envfile" ]; then
        set -a
        . "$envfile"
        set +a
      else
        echo "assistant-vault-sync: $envfile missing; Discogs sync skipped until DISCOGS_TOKEN is placed (see README)." >&2
      fi
      exec /command/s6-setuidgid assistant \
        env \
          HOME=/var/lib/assistant \
          USER=assistant \
          SHELL=/bin/sh \
          PATH=/etc/profiles/per-user/assistant/bin:/nix/var/nix/profiles/default/bin:/bin:/sbin:/usr/bin \
          SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
          NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
          NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-bundle.crt \
          OBSIDIAN_VAULT_DIR="$vault" \
        ${pkgs.supercronic}/bin/supercronic ${vaultSyncCrontab}
    '';
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
