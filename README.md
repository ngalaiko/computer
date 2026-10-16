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

The exe.dev VM runs NixOS (`nixosConfigurations.exedev`) with systemd as PID 1:
exe.dev's init execs an image `Cmd` named `init`, and the image's `/init`
boots the current system profile. The provider owns the kernel, network, DNS,
`/etc/hosts` and `/etc/hostname`.

Everyday deploys are **in place** with `nixos-rebuild switch`, so the Tailscale
node, the public URL, and all on-disk state are preserved:

- **From your Mac:** `nix run .#deploy`. Builds in the box's own store over
  Tailscale (the Mac is aarch64, the box x86_64) and switches it.
- **From CI:** `.github/workflows/deploy.yaml` runs after a green `build` on
  `master` and is **self-deciding**:
  - **no VM tagged `computer`** → it `exe.dev new`s one from the built image
    (bootstrap / disaster recovery), passing the backup secrets so the box can
    restore from B2 on boot. This is the only path that uses `RESTIC_PASSWORD` /
    `B2_ACCOUNT_KEY` (CI secrets).
  - **VM exists** → it switches in place (`nix run .#deploy`) with **no app
    secrets** — runtime secrets already live on the box. This path needs only
    tailnet access: a Tailscale OAuth client tagged `tag:ci` (client id inline in
    `deploy.yaml`, secret in the `TS_OAUTH_SECRET` repo secret) and a policy rule
    letting `tag:ci` SSH the computer node:

    ```jsonc
    "ssh": [{ "action": "accept", "src": ["tag:ci"],
              "dst": ["tag:computer"], "users": ["nikita"] }]
    ```

Roll back with `nixos-rebuild switch --rollback --target-host nikita@computer --sudo`.
`exe.dev restart` boots the latest generation; only the image's `/init` is fixed
at create time.

Service logs are in the journal: `journalctl -u <service>`.

### Cutover from the s6 image

The s6-based image can't switch in place to NixOS; the box must be recreated.
Before deleting it, take a snapshot of every home on the **old** box, under the
host and tag the new box restores from:

```sh
sudo sh -c '
  set -eu
  cd /run/s6/container_environment
  for v in RESTIC_REPOSITORY RESTIC_PASSWORD B2_ACCOUNT_ID B2_ACCOUNT_KEY; do
    export "$v=$(cat "$v")"
  done
  export RESTIC_CACHE_DIR=/var/cache/restic
  restic unlock
  restic backup --host exedev --tag auto \
    --exclude __pycache__ --exclude .venv --exclude venv --exclude node_modules \
    --exclude "!**/.pi/**/node_modules" --exclude .cache \
    --exclude checkpoints --exclude backups \
    /home/nikita /var/lib/amp /var/lib/tailscale/authkey
  restic snapshots --host exedev --tag auto --latest 1
  restic ls latest /home/nikita /var/lib/amp | head -50
'
```

Stop writers first (Obsidian sync, amp runner) if the snapshot must be exact.
Then delete the VM and let CI create a new one; `backup-restore` restores the
snapshot on first boot and home-manager links the dotfiles over the restored
copies, moving those aside with a `.backup` suffix.

## After creating a machine

One-time steps that place secrets; backups persist them across recreations
(confirm a snapshot ran: `journalctl -u restic-backups-b2`). nikita's ssh key
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
   `systemctl restart tailscaled-autoconnect`), then
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

5. Place the wherenow bearer token (the value the "Where Now?" iOS app sends as
   `Authorization: Bearer …`) so the `wherenow` service can start.
   The runtime env file is kept out of this (public) repo
   and the image, and backed up under nikita's home so it survives
   recreation:

   ```
   sudo install -d -o 1000 -g 1000 -m 700 /home/nikita/.config/wherenow
   sudo sh -c 'umask 077; printf "TOKEN=%s\n" "<bearer-token>" > /home/nikita/.config/wherenow/env'
   sudo chown 1000:1000 /home/nikita/.config/wherenow/env
   ```

   Then point the iOS app at `https://computer.<tailnet>.ts.net/assistant/wherenow`
   with the same token; the root caddy routes it to wherenow on loopback 8085.
   wherenow writes each position straight into nikita's Obsidian vault as a
   note; the service retries every 10s until the file exists.

6. **(Optional)** Place a Discogs personal access token so `vault-sync`
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

7. Place an Amp access token so `amp-runner` can serve threads started on
   ampcode.com (runner id `computer`). Get it at
   <https://ampcode.com/settings/security#access-token>:

   ```
   sudo install -d -o 2002 -g 2002 -m 700 /var/lib/amp/.config/amp-runner
   sudo sh -c 'umask 077; printf "AMP_API_KEY=%s\n" "<token>" > /var/lib/amp/.config/amp-runner/env'
   sudo chown 2002:2002 /var/lib/amp/.config/amp-runner/env
   ```

   Amp and its coding tools are installed for the unprivileged `amp` user.
   The runner starts in `/var/lib/amp` without creating or updating
   checkouts. The agent owns its home contents: repositories, instructions,
   skills, integration launchers, credentials, and private configuration. The
   whole home is covered by backups and restored before the runner starts.
   Deployment does not seed instructions or skills, or impose private data paths.
   User-owned runner settings are loaded as `amp`, not root, from the env file
   above. The service retries every 30s until the token is configured. The runner
   automatically discovers Git checkouts up to three levels beneath `/var/lib/amp`,
   including repositories cloned into `~amp/src` while it runs. For directories
   outside the amp home, use `amp runner dirs add <path>` as the `amp` user.

   The runner enables `--remote-control-terminal`, allowing terminal access
   from ampcode.com for its threads. Terminals run as the unprivileged `amp`
   user; this uses Amp's connection, not a public Caddy route.

   Chromium and `agent-browser` are installed for `amp`. The runner exports
   `AGENT_BROWSER_EXECUTABLE_PATH` pointing to the packaged Chromium wrapper,
   and `FONTCONFIG_FILE` supplies pinned DejaVu fonts. Browser tools need no
   separate browser download or host font installation.

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

## Vault ownership

The Vault lives at `/home/nikita/Vault`. Obsidian Sync, Letterboxd/Discogs polls,
and Where Now all run as `nikita`. Sync tools are installed for `nikita`;
`amp` has direct read/write access to notes, not nikita's sync credentials. Vault data, Obsidian login/sync state, and both runtime env
directories are backed up.

`vault-permissions` runs after backup restore and when its unit changes. It sets nikita as
the owner, replaces existing Vault ACLs with access for nikita and amp, and installs default ACLs on
every directory so normal new files remain shared even with a restrictive
umask. Tools that explicitly create files with mode `0600`, preserve foreign
ACLs, or move files in from elsewhere can bypass inheritance; run
`sudo /etc/profiles/per-user/nikita/bin/vault-permissions` to repair access.
The remote filesystem must support POSIX ACLs; stop and investigate if
`setfacl` reports an error rather than falling back to world-writable notes.

## Configuration

### Backups

We have to store it outside of the machine to be able to restore everything else on startup.

`exedev.backup.paths` are snapshotted every 15 minutes by
`services.restic.backups.b2` and restored on every boot by `backup-restore`.
The variables below are passed to `exe.dev new --env`; `/init` writes them to
the root-only `/run/exedev/environment`, which only the restic units read.

| Variable            | Description                              |
| ------------------- | ---------------------------------------- |
| `RESTIC_REPOSITORY` | B2 restic repo, e.g. `b2:backups:exedev` |
| `RESTIC_PASSWORD`   | restic repo encryption password          |
| `B2_ACCOUNT_ID`     | B2 key id                                |
| `B2_ACCOUNT_KEY`    | B2 application key (scope to the bucket) |
