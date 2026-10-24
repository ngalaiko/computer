# computer

My Mac and an [exe.dev](https://exe.dev) cloud machine, configured with Nix.

## Home Manager

All my tools and dotfiles live in [`home`](home), shared across both machines.

## MacBook

My local workstation, managed with nix-darwin and Home Manager, with Homebrew
for Mac apps.

## exe.dev

The cloud runs NixOS with separate accounts for me and personal agents. Restic
backs up their homes and service credentials to Backblaze B2 every 15 minutes
and restores them on a fresh disk. Deployment applies the Nix configuration
in place over Tailscale SSH.

Each account manages its own Caddy routes without root access, publishing web
services through exe.dev and Tailscale Funnel. Funnel routes are public;
applications handle authentication.

## Rex

I use [Rex](https://www.superlogical.com/rex/docs) and [Tailscale](https://tailscale.com) to
work seamlessly across both machines, with local and remote terminal sessions
in the same app.

## Amp

I use [Amp](https://ampcode.com) as both a personal agent and a coding agent,
with exe.dev providing remote runners that keep working independently of my Mac.

## Obsidian

I sync my [Obsidian](https://obsidian.md) vault between machines with Obsidian Sync
and chat with it through Amp. Personal agents manage the vault; Where Now? saves
location updates, and background jobs import data from Discogs and Letterboxd.
