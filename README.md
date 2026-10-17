# computer

Nix configuration for my Mac and remote [exe.dev](https://exe.dev) machine.

- `hosts/macbook`: nix-darwin configuration.
- `hosts/exedev`: NixOS configuration and user accounts.
- `home`: Home Manager configuration.
- `modules`, `packages`, `scripts`: shared modules, packages, and deployment tools.

```sh
darwin-rebuild switch --flake .#macbook # Apply Mac configuration
nix run .#deploy                      # Deploy to exedev over Tailscale
nix fmt                               # Format
nix flake check                       # Check
```
