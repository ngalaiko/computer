[![ghcr.io](https://img.shields.io/badge/ghcr.io-ngalaiko%2Fcomputer.exe-blue?logo=docker&logoColor=white)](https://github.com/ngalaiko/computer/pkgs/container/computer.exe)

# computer

A Nix-built OCI image to bootstrap [exe.dev](https://exe.dev) machine.

## Mac setup

Local builds offload to a nix-darwin **linux-builder VM** (both arches,
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

## Launch

```fish
ssh exe.dev new --image=ghcr.io/ngalaiko/computer.exe:latest --name computer
ssh computer.exe.xyz
```
