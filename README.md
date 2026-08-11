[![ghcr.io](https://img.shields.io/badge/ghcr.io-ngalaiko%2Fcomputer.exe-blue?logo=docker&logoColor=white)](https://github.com/ngalaiko/computer/pkgs/container/computer.exe)

# computer

nix files for:
- my mac
- my remote [exe.dev](https://exe.dev) machine

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

4. Enable **HTTPS Certificates** (admin console → DNS → *Enable HTTPS*, needs
   MagicDNS on). Required to provision the `*.ts.net` certs. The `computer`
   node's `tailscale-serve` service re-asserts this on every boot:
   - `https://computer.<tailnet>.ts.net/<tenant>/` → ingress, **public via
     Funnel** (needs the `nodeAttrs` above). Unauthenticated — see the note in
     `hosts/exedev/default.nix`. This one is named after the *node*, so on a
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
   and the image, and backed up under the assistant home so it survives
   recreation:

   ```
   sudo install -d -o 2001 -g 2001 -m 700 /var/lib/assistant/.config/wherenow
   sudo sh -c 'umask 077; printf "TOKEN=%s\n" "<bearer-token>" > /var/lib/assistant/.config/wherenow/env'
   sudo chown 2001:2001 /var/lib/assistant/.config/wherenow/env
   ```

   Then point the iOS app at `https://computer.<tailnet>.ts.net/assistant/wherenow`
   with the same token — wherenow is fronted by the assistant's own caddy. On a
   box that already has `~assistant/.caddy/Caddyfile`, add the `/wherenow/*`
   handle to it once (or delete the file to let the seed regenerate) and reload
   caddy, since the seed only writes when the file is absent. wherenow writes
   each position straight into the assistant's Obsidian vault as a note; the
   service retries every 10s until the file exists.

7. **(Optional)** Place a Discogs personal access token so `assistant-vault-sync`
   can sync your record collection + wantlist into Album notes. Letterboxd is
   public and needs nothing; without this file only the Discogs half is skipped.
   Get the token at <https://www.discogs.com/settings/developer>. Same runtime
   env-file pattern, backed up under the assistant home:

   ```
   sudo install -d -o 2001 -g 2001 -m 700 /var/lib/assistant/.config/vault-sync
   sudo sh -c 'umask 077; printf "DISCOGS_TOKEN=%s\n" "<token>" > /var/lib/assistant/.config/vault-sync/env'
   sudo chown 2001:2001 /var/lib/assistant/.config/vault-sync/env
   ```

   Optionally add `LETTERBOXD_USERNAME=…` / `DISCOGS_USERNAME=…` lines (both
   default to `ngalaiko`). The scripts are additive: a new movie or record
   becomes a note, a repeat watch appends a `watched:` date, and a wishlist
   record you buy gets its blank `lp:` filled — hand edits are never clobbered.

## Configuration

### Backups

We have to store it outside of the machine to be able to restore everything else on startup.

| Variable | Description |
| --- | --- |
| `RESTIC_REPOSITORY` | B2 restic repo, e.g. `b2:backups:exedev` |
| `RESTIC_PASSWORD` | restic repo encryption password |
| `B2_ACCOUNT_ID` | B2 key id |
| `B2_ACCOUNT_KEY` | B2 application key (scope to the bucket) |
