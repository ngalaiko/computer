[![ghcr.io](https://img.shields.io/badge/ghcr.io-ngalaiko%2Fcomputer.exe-blue?logo=docker&logoColor=white)](https://github.com/ngalaiko/computer/pkgs/container/computer.exe)

# computer

A Nix-built OCI image to bootstrap [exe.dev](https://exe.dev) machine.

## Components

- **exe.dev image** — s6-supervised: OpenSSH, the Hermes agent (behind a caddy
  proxy), tailscaled (persistent tailnet node with Tailscale SSH), restic
  backups to B2 with restore-on-boot, and a nix daemon for runtime installs.
- **Users** — `nikita` (login user, fish shell, home-manager env, sudo) and
  `hermes` (the agent: own package set, no sudo, not nix-trusted).
- **Mac** — nix-darwin + home-manager consuming the same `home/` modules;
  remaining homebrew (casks, mas apps) declared in `hosts/macbook/homebrew.nix`.

## After creating a machine

One-time steps that place secrets; backups persist them across recreations
(confirm a snapshot ran: `cat /var/log/backup-cron/current`).

1. Create the VM with the backup env vars below attached.
2. Generate nikita's per-machine ssh key and register it with GitHub as both
   auth and signing key:

   ```
   ssh-keygen -t ed25519
   gh ssh-key add ~/.ssh/id_ed25519.pub --title exedev --type authentication
   gh ssh-key add ~/.ssh/id_ed25519.pub --title exedev --type signing
   ```

3. Create the tailscale secret: an [OAuth client](https://login.tailscale.com/admin/settings/oauth)
   with the **Keys → Auth Keys: write** scope, tagged `tag:exedev`. The
   [tailnet policy](https://login.tailscale.com/admin/acls) must define the
   tag and allow ssh into it:

   ```jsonc
   "tagOwners": { "tag:exedev": ["autogroup:admin"] },
   "ssh": [{
     "action": "accept",
     "src":    ["ngalaiko@github"],
     "dst":    ["tag:exedev"],
     "users":  ["nikita"]
   }]
   ```

   Place the secret on the machine (non-ephemeral, so the node persists):

   ```
   sudo mkdir -p /var/lib/tailscale
   sudo sh -c 'umask 077; printf %s "tskey-client-…?preauthorized=true&ephemeral=false" > /var/lib/tailscale/authkey'
   ```

   Reboot (or run the `tailscale up` from `modules/exedev/services/tailscale.nix`
   by hand), then `tailscale ssh nikita@exedev` over the tailnet.

## Configuration

### Backups

We have to store it outside of the machine to be able to restore everything else on startup.

| Variable | Description |
| --- | --- |
| `RESTIC_REPOSITORY` | B2 restic repo, e.g. `b2:my-bucket:hermes` |
| `RESTIC_PASSWORD` | restic repo encryption password |
| `B2_ACCOUNT_ID` | B2 key id |
| `B2_ACCOUNT_KEY` | B2 application key (scope to the bucket) |
