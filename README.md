[![ghcr.io](https://img.shields.io/badge/ghcr.io-ngalaiko%2Fcomputer.exe-blue?logo=docker&logoColor=white)](https://github.com/ngalaiko/computer/pkgs/container/computer.exe)

# computer

nix files for:
- my mac
- remove [exe.dev](https://exe.dev) machine

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
   "nodeAttrs": [{ "target": ["tag:computer"], "attr": ["funnel"] }],
   // the cptr dashboard is a Tailscale Service: let tag:computer nodes host it
   // without manual approval, and let my devices reach it. The svc:cptr name
   // lives here (in the tailnet), so it outlives any single machine.
   "autoApprovers": { "services": { "svc:cptr": ["tag:computer"] } },
   "grants": [{ "src": ["autogroup:member"], "dst": ["svc:cptr"], "ip": ["443"] }]
   ```

   Tailscale Services are configured in the policy, not on the box. If your
   tailnet requires the Service object to exist before it can be hosted, add it
   once under **Services → Add a service** (`svc:cptr`) — a one-time tailnet
   step, not per-machine.

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
   node's `tailscale-serve` service re-asserts both on every boot:
   - `https://cptr.<tailnet>.ts.net/` → cptr dashboard, **tailnet-private**, a
     Tailscale **Service** (`svc:cptr`). Because the Service is defined in the
     tailnet, this URL is **stable across recreations** — a fresh machine just
     re-hosts it (auto-approved) even though it registers as a new node.
   - `https://computer.<tailnet>.ts.net/<tenant>/` → ingress, **public via
     Funnel** (needs the `nodeAttrs` above). Unauthenticated — see the note in
     `hosts/exedev/default.nix`. This one is named after the *node*, so on a
     recreation where the retired ephemeral node hasn't dropped yet Tailscale
     may suffix it (`computer-1`) until the stale one is culled; exe.dev's
     public share is the stable public path if that matters.

## Configuration

### Backups

We have to store it outside of the machine to be able to restore everything else on startup.

| Variable | Description |
| --- | --- |
| `RESTIC_REPOSITORY` | B2 restic repo, e.g. `b2:backups:exedev` |
| `RESTIC_PASSWORD` | restic repo encryption password |
| `B2_ACCOUNT_ID` | B2 key id |
| `B2_ACCOUNT_KEY` | B2 application key (scope to the bucket) |
