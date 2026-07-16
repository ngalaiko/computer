[![ghcr.io](https://img.shields.io/badge/ghcr.io-ngalaiko%2Fcomputer.exe-blue?logo=docker&logoColor=white)](https://github.com/ngalaiko/computer/pkgs/container/computer.exe)

# computer

A Nix-built OCI image to bootstrap [exe.dev](https://exe.dev) machine.

## Layout

- `flake.nix` — inputs and output plumbing
- `modules/exedev/` — the image module system (mechanism, no policy)
- `hosts/exedev/` — the image configuration; per-user packages/env under `users/`
- `hosts/mac/` — this Mac (nix-darwin), including the linux-builder VM
- `packages/` — standalone packages (agent-browser, s6-overlay, release scripts)

## Configuration

### Backups

We have to store it outside of the machine to be able to restore everything else on startup.

| --- | --- |
| `RESTIC_REPOSITORY` | B2 restic repo, e.g. `b2:my-bucket:hermes` | 
| `RESTIC_PASSWORD` | restic repo encryption password |
| `B2_ACCOUNT_ID` | B2 key id | 
| `B2_ACCOUNT_KEY` | B2 application key (scope to the bucket) | 
