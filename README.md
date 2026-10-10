[![ghcr.io](https://img.shields.io/badge/ghcr.io-ngalaiko%2Fcomputer.exe-blue?logo=docker&logoColor=white)](https://github.com/ngalaiko/computer/pkgs/container/computer.exe)

# computer

nix files for:

- my mac
- my remote [exe.dev](https://exe.dev) machine

## Bootstrapping a Mac

The Darwin target is `.#macbook` for user `nikita` on Apple Silicon.

On a fresh Mac:

```sh
xcode-select --install
curl -fsSL https://install.determinate.systems/nix | sh -s -- install

mkdir -p ~/src
git clone https://github.com/ngalaiko/computer.git ~/src/computer
cd ~/src/computer

nix --extra-experimental-features 'nix-command flakes' \
  run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
  switch --flake .#macbook
```

The explicit experimental features are only for the first bootstrap; this config
enables `nix-command` and `flakes` permanently after a successful switch. Sign in
to the Mac App Store before rebuilding, because `hosts/macbook/homebrew.nix`
installs `masApps`. If MAS blocks the first run, temporarily set `masApps = {};`,
rebuild, then restore the file after signing in:

```sh
git checkout -- hosts/macbook/homebrew.nix
```

Do not run `brew bundle` or `darwin-rebuild` with `sudo`. If Homebrew permission
errors appear after a mistaken sudo run, repair the Apple Silicon prefix, then run
the rebuild normally:

```sh
sudo chown -R nikita:admin /opt/homebrew
sudo mkdir -p /opt/homebrew/{Cache,Logs}
sudo chown -R nikita:admin /opt/homebrew/{Cache,Logs}
```

The Homebrew module is declarative and removes unlisted formulae/casks, so avoid
installing ad-hoc packages before the first rebuild.

## Deploying

Everyday deploys are **in place** — they update the running VM without recreating
it, so the Tailscale node, the public URL, and all on-disk state are preserved, and
only changed services reload (unchanged ones keep their PIDs):

- **From your Mac:** `nix run .#deploy`. Builds the system generation, ships its
  closure to the box over Tailscale, and runs `<gen>/activate switch`. The Mac is
  aarch64 and the box is x86_64, so the build is realised in the box's own store.
- **From CI:** `.github/workflows/deploy.yaml` runs after a green `build` on
  `master` and is **self-deciding**:
  - **no VM tagged `computer`** → it `exe.dev new`s one from the built image
    (bootstrap / disaster recovery), passing the backup secrets so the box can
    restore from B2 on boot. This is the only path that uses `RESTIC_PASSWORD` /
    `B2_ACCOUNT_KEY` (CI secrets).
  - **VM exists** → it activates in place (`nix run .#deploy`) with **no app
    secrets** — RESTIC/B2/pilegram already live on the box. This path needs only
    tailnet access: a Tailscale OAuth client tagged `tag:ci` (client id inline in
    `deploy.yaml`, secret in the `TS_OAUTH_SECRET` repo secret) and a policy rule
    letting `tag:ci` SSH the computer node:

    ```jsonc
    "ssh": [{ "action": "accept", "src": ["tag:ci"],
              "dst": ["tag:computer"], "users": ["nikita"] }]
    ```

Roll back with `sudo nix-env -p /nix/var/nix/profiles/system --rollback` then
re-run `activate`. `sudo <gen>/activate test` is a dry run that prints the
overlay/reload plan and changes nothing.

**Base changes still take effect only through a create** (s6-overlay / nix / kernel
layer, the init/mount wrapper, `image.env`): they're excluded from in-place
activation, so they land when CI next has to create a VM — or when you `rm` the VM
to force a fresh one. After a create, the next `deploy` re-establishes the latest
generation, and the base `init-wrapper` hands off to it on `exe.dev restart`.

## After creating a machine

One-time steps that place secrets; backups persist them across recreations
(confirm a snapshot ran: `cat /var/log/backup-cron/current`). nikita's ssh key
(`~/.ssh`) and the tailscale authkey are both backed up, so neither is
re-placed on recreation. Each tailscale node's state lives in its own statedir
on the persistent disk but isn't backed up, so a fresh machine registers new
nodes; use an ephemeral key so retired ones auto-clean (see step 3).

1. Create the VM with the backup env vars below attached.
2. Generate nikita's per-machine ssh key and register it with GitHub as both
   auth and signing key:

   ```
   ssh-keygen -t ed25519
   gh ssh-key add ~/.ssh/id_ed25519.pub --title exedev --type authentication
   gh ssh-key add ~/.ssh/id_ed25519.pub --title exedev --type signing
   ```

3. Create the tailscale secret: an [OAuth client](https://login.tailscale.com/admin/settings/oauth)
   with the **Keys → Auth Keys: write** scope, tagged `tag:computer`. The
   [tailnet policy](https://login.tailscale.com/admin/acls) must define the
   tag and allow ssh into it:

   ```jsonc
   "tagOwners": { "tag:computer": ["autogroup:admin"] },
   "ssh": [{
     "action": "accept",
     "src":    ["ngalaiko@github"],
     "dst":    ["tag:computer"],
     "users":  ["nikita"]
   }],
   // required for `funnel = true` serve entries (the public ingress).
   "nodeAttrs": [{ "target": ["tag:computer"], "attr": ["funnel"] }]
   ```

   Place the secret on the machine (ephemeral, so retired VMs' nodes auto-clean):

   ```
   sudo mkdir -p /var/lib/tailscale
   sudo sh -c 'umask 077; printf %s "tskey-client-…?preauthorized=true&ephemeral=true" > /var/lib/tailscale/authkey'
   ```

   Reboot (or run the per-node `tailscale up` from
   `modules/exedev/services/tailscale.nix` by hand), then
   `tailscale ssh nikita@computer` over the tailnet. The authkey is backed up so
   you don't re-place it, and it registers every node. Each tailscaled keeps its
   node key (and, for the ssh node, its SSH host keys) in its own persistent
   statedir (not backed up), so a fresh machine registers new nodes; the
   ephemeral key lets retired ones auto-remove once offline — no manual cleanup.

4. Enable **HTTPS Certificates** (admin console → DNS → _Enable HTTPS_, needs
   MagicDNS on). Required to provision the `*.ts.net` certs. The `computer`
   node's `tailscale-serve` service re-asserts this on every boot:
   - `https://computer.<tailnet>.ts.net/<tenant>/` → ingress, **public via
     Funnel** (needs the `nodeAttrs` above). Unauthenticated — see the note in
     `hosts/exedev/default.nix`. This one is named after the _node_, so on a
     recreation where the retired ephemeral node hasn't dropped yet Tailscale
     may suffix it (`computer-1`) until the stale one is culled; exe.dev's
     public share is the stable public path if that matters.

5. Place the Telegram gateway (pilegram) secrets — the bot token and your
   allow-listed Telegram user id(s) — so the `assistant-gateway` service can
   start. They stay out of this (public) repo and the image; the file lives
   under the assistant home and is backed up, so it's restored on recreation:

   ```
   sudo install -d -o 2001 -g 2001 -m 700 /var/lib/assistant/.config/pilegram
   sudo sh -c 'umask 077; printf "TELEGRAM_BOT_TOKEN=%s\nPILEGRAM_ALLOW=%s\n" "123456:AA..." "111222333" > /var/lib/assistant/.config/pilegram/env'
   sudo chown 2001:2001 /var/lib/assistant/.config/pilegram/env
   ```

   `PILEGRAM_ALLOW` is comma-separated numeric Telegram user ids. In BotFather,
   enable **Threaded Mode** so each Telegram topic is its own agent session. The
   service retries every 10s until the file exists.

6. Place the wherenow bearer token (the value the "Where Now?" iOS app sends as
   `Authorization: Bearer …`) so the `assistant-wherenow` service can start.
   Same runtime env-file pattern as pilegram — kept out of this (public) repo
   and the image, and backed up under nikita's home so it survives
   recreation:

   ```
   sudo install -d -o 1000 -g 1000 -m 700 /home/nikita/.config/wherenow
   sudo sh -c 'umask 077; printf "TOKEN=%s\n" "<bearer-token>" > /home/nikita/.config/wherenow/env'
   sudo chown 1000:1000 /home/nikita/.config/wherenow/env
   ```

   Then point the iOS app at `https://computer.<tailnet>.ts.net/assistant/wherenow`
   with the same token — wherenow is fronted by the assistant's own caddy. On a
   box that already has `~assistant/.caddy/Caddyfile`, add the `/wherenow/*`
   handle to it once (or delete the file to let the seed regenerate) and reload
   caddy, since the seed only writes when the file is absent. wherenow writes
   each position straight into nikita's Obsidian vault as a note; the
   service retries every 10s until the file exists.

7. **(Optional)** Place a Discogs personal access token so `assistant-vault-sync`
   can sync your record collection + wantlist into Album notes. Letterboxd is
   public and needs nothing; without this file only the Discogs half is skipped.
   Get the token at <https://www.discogs.com/settings/developer>. Same runtime
   env-file pattern, backed up under nikita's home:

   ```
   sudo install -d -o 1000 -g 1000 -m 700 /home/nikita/.config/vault-sync
   sudo sh -c 'umask 077; printf "DISCOGS_TOKEN=%s\n" "<token>" > /home/nikita/.config/vault-sync/env'
   sudo chown 1000:1000 /home/nikita/.config/vault-sync/env
   ```

   Optionally add `LETTERBOXD_USERNAME=…` / `DISCOGS_USERNAME=…` lines (both
   default to `ngalaiko`). The scripts are additive: a new movie or record
   becomes a note, a repeat watch appends a `watched:` date, and a wishlist
   record you buy gets its blank `lp:` filled — hand edits are never clobbered.

8. Place an Amp access token so `amp-runner` can serve threads started on
   ampcode.com (runner id `computer`). Get it at
   <https://ampcode.com/settings/security#access-token>:

   ```
   sudo install -d -o 2002 -g 2002 -m 700 /var/lib/amp/.config/amp-runner
   sudo sh -c 'umask 077; printf "AMP_API_KEY=%s\n" "<token>" > /var/lib/amp/.config/amp-runner/env'
   sudo chown 2002:2002 /var/lib/amp/.config/amp-runner/env
   ```

   Amp and its coding tools are installed for the unprivileged `amp` user. The
   runner checks out <https://github.com/ngalaiko/assistant> into `~amp/assistant`
   (`/var/lib/amp/assistant`) and starts there, making that repository its default
   project root. Existing files are preserved; a checkout conflict stops
   startup rather than overwriting them. Subsequent starts do not reset or pull
   the working tree. Amp config, credentials and project files are covered by
   the amp home backup. The existing token and settings paths are unchanged; no
   account migration is needed. The service retries every 30s until the env file
   exists. Add other checkouts with `amp runner dirs add <path>` as the `amp` user.

   The runner enables `--remote-control-terminal`, allowing terminal access
   from ampcode.com for its threads. Terminals run as the unprivileged `amp`
   user; this uses Amp's connection, not a public Caddy route.

   Chromium and `agent-browser` are installed for `amp`. The runner exports
   `AGENT_BROWSER_EXECUTABLE_PATH` pointing to the packaged Chromium wrapper,
   so browser tools use it rather than downloading a separate browser.

   Amp can serve HTTP under `https://computer.<tailnet>.ts.net/amp/` through
   its own Caddy on port 8084. As the `amp` user, edit `~/.caddy/Caddyfile` to
   add routes inside the `:8084` site block, then validate and reload:

   ```sh
   caddy validate --config ~/.caddy/Caddyfile --adapter caddyfile
   caddy reload --config ~/.caddy/Caddyfile --adapter caddyfile --address unix//run/ingress-amp/admin.sock
   ```

   The root proxy strips `/amp` before forwarding, so a tenant route `/demo/*`
   is reached at `/amp/demo/*`. Routes default to 404 until configured; the
   Caddyfile is preserved across deploys and covered by the amp home backup.
   Funnel access is public and unauthenticated: add authentication for private
   content, and keep backend servers on loopback.

## Vault ownership and migration

The Vault lives at `/home/nikita/Vault`. Obsidian Sync, Letterboxd/Discogs polls,
and Where Now all run as `nikita`. The existing `assistant-*` service names and
`/assistant/wherenow` URL are retained. Sync tools are installed for `nikita`;
`amp` and `assistant` have direct read/write access to notes, not nikita's sync
credentials. Vault data, Obsidian login/sync state, and both runtime env
directories are backed up.

`vault-permissions` runs after backup restore and on deploy. It sets nikita as
the owner, replaces existing Vault ACLs with access for these three users, and installs default ACLs on
every directory so normal new files remain shared even with a restrictive
umask. Tools that explicitly create files with mode `0600`, preserve foreign
ACLs, or move files in from elsewhere can bypass inheritance; run
`sudo /etc/profiles/per-user/nikita/bin/vault-permissions` to repair access.
The remote filesystem must support POSIX ACLs; stop and investigate if
`setfacl` reports an error rather than falling back to world-writable notes.

### Move an existing assistant Vault

Run these on the **remote computer**, before deploying this refactor. Stop
manual syncs and agent edits too. The script refuses to overwrite any of the
destination directories. It moves Obsidian's separate global state as well as
the Vault; moving only the Vault would lose the login and local sync tracking.

```sh
sudo /bin/sh <<'SH'
set -eu
for name in Vault .config/obsidian-headless .config/vault-sync .config/wherenow; do
  test ! -e "/home/nikita/$name" || {
    echo "Destination exists: /home/nikita/$name; inspect it before migrating." >&2
    exit 1
  }
done
test -d /var/lib/assistant/Vault/.obsidian
test -d /var/lib/assistant/.config/obsidian-headless/sync

for service in assistant-obsidian-sync assistant-vault-sync assistant-wherenow; do
  /command/s6-svc -d "/run/service/$service"
  /command/s6-svc -wd -T 30000 "/run/service/$service"
done

install -d -o 1000 -g 1000 /home/nikita/.config
mv /var/lib/assistant/Vault /home/nikita/Vault
for app in obsidian-headless vault-sync wherenow; do
  if [ -d "/var/lib/assistant/.config/$app" ]; then
    mv "/var/lib/assistant/.config/$app" /home/nikita/.config/
  fi
done

# Headless 0.0.14 registers an absolute vaultPath in config.json. Update only
# that path while stopped; preserve encryption keys, settings, and state.db.
umask 077
for config in /home/nikita/.config/obsidian-headless/sync/*/config.json; do
  test -f "$config" || continue
  tmp=$(mktemp "$config.XXXXXX")
  /etc/profiles/per-user/assistant/bin/jq '
    if .vaultPath == "/var/lib/assistant/Vault"
    then .vaultPath = "/home/nikita/Vault" else . end
  ' "$config" > "$tmp"
  mv "$tmp" "$config"
done

chown -R 1000:1000 /home/nikita/Vault
for app in obsidian-headless vault-sync wherenow; do
  dir="/home/nikita/.config/$app"
  if [ -d "$dir" ]; then
    chown -R 1000:1000 "$dir"
    chmod -R u+rwX,go-rwx "$dir"
  fi
done
SH
```

Then deploy from your checkout (`nix run .#deploy`). Deployment installs the
ACL tools, reapplies Vault permissions, and restarts the changed services as
nikita. Do not restart the old services before deployment: they still target
the old location. Do not reboot until a backup of the migrated paths succeeds.

On the remote computer, as `nikita`, verify the registration and exercise
access in **both directions** (including inheritance with `umask 077`):

```sh
/etc/profiles/per-user/nikita/bin/ob sync-status --path /home/nikita/Vault --json
sudo /etc/profiles/per-user/nikita/bin/vault-permissions
/etc/profiles/per-user/nikita/bin/getfacl /home/nikita /home/nikita/Vault

sudo /bin/sh <<'SH'
set -eu
for user in nikita amp assistant; do
  sudo -u "$user" sh -c '
    umask 077
    mkdir /home/nikita/Vault/.permission-check-"$1"
    printf "%s\n" "$1" > /home/nikita/Vault/.permission-check-"$1"/note
  ' sh "$user"
done
for user in nikita amp assistant; do
  sudo -u "$user" sh -c '
    for owner in nikita amp assistant; do
      file=/home/nikita/Vault/.permission-check-$owner/note
      cat "$file"
      printf "%s\n" "$1" >> "$file"
    done
  ' sh "$user"
done
rm -r /home/nikita/Vault/.permission-check-nikita \
  /home/nikita/Vault/.permission-check-amp \
  /home/nikita/Vault/.permission-check-assistant
SH

ps -eo user,args | grep -E 'ob sync|supercronic.*vault-sync|bin/wherenow'
tail /var/log/assistant-obsidian-sync/current
tail /var/log/assistant-vault-sync/current
tail /var/log/assistant-wherenow/current
```

Confirm `/var/log/backup-cron/current` shows a successful snapshot containing
the new paths before considering migration finished. On a fresh machine with
no existing Vault, run `ob login`, `ob sync-list-remote`, and
`ob sync-setup --vault <remote-vault-id> --path /home/nikita/Vault` as nikita.

## Configuration

### Backups

We have to store it outside of the machine to be able to restore everything else on startup.

| Variable            | Description                              |
| ------------------- | ---------------------------------------- |
| `RESTIC_REPOSITORY` | B2 restic repo, e.g. `b2:backups:exedev` |
| `RESTIC_PASSWORD`   | restic repo encryption password          |
| `B2_ACCOUNT_ID`     | B2 key id                                |
| `B2_ACCOUNT_KEY`    | B2 application key (scope to the bucket) |
