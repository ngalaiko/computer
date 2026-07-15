[![ghcr.io](https://img.shields.io/badge/ghcr.io-ngalaiko%2Fcomputer.exe-blue?logo=docker&logoColor=white)](https://github.com/ngalaiko/computer/pkgs/container/computer.exe)

# computer

A Nix-built OCI image to bootstrap [exe.dev](https://exe.dev) machine.

## Mac setup

Local builds offload to a nix-darwin linux-builder VM (both arches,
x86_64 via emulation), configured in `hosts/mac/default.nix`:

```bash
# first time (bootstraps nix-darwin)
sudo nix run nix-darwin/nix-darwin-25.11#darwin-rebuild -- switch --flake .#mac

# after that
sudo darwin-rebuild switch --flake .#mac
```

## Build & publish

```bash
# one-time: grant gh the write:packages scope for GHCR
nix run .#ghcr-auth

# build both arches, push, stitch the multi-arch manifest
nix run .#release
```

## Configuration

### Backups

| --- | --- | --- |
| `RESTIC_REPOSITORY` | B2 restic repo, e.g. `b2:my-bucket:hermes` | 
| `RESTIC_PASSWORD` | restic repo encryption password |
| `B2_ACCOUNT_ID` | B2 key id | 
| `B2_ACCOUNT_KEY` | B2 application key (scope to the bucket) | 

## Skills

This repo ships [Hermes Agent skills](docs/skills/) for agents running on this VM,
covering the update workflow and environment conventions.

| Skill | Description |
|-------|-------------|
| `computer-self-update` | PR workflow for updating the VM through changes to this repo | 
