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

## Rex on the cloud machine

The `rex-login-server` service accepts the Tailscale principal
`ngalaiko@github` as the Linux account `nikita`. On the Mac, with Tailscale
connected, choose **Add Remote Host…** in Rex and enter
`http://nikita@exedev.tail4fad0.ts.net:7297`. Tailscale encrypts the connection;
this listener is separate from the public Funnel on port 443.

Rex's snapshot packages currently require a package token. Provision
`/etc/nix/rex.netrc` outside this repository, owned by root with mode `0600`,
containing `machine pkgs.superlogical.com login rex password YOUR_TOKEN`.
The cloud Nix configuration uses that file and includes it in the existing
encrypted restic backups, restored to the same path on a fresh disk.
The machine fetching the flake
inputs also needs authentication before the first deployment; for example,
use `sudo nix flake lock --option netrc-file /etc/nix/rex.netrc` from a checkout
on the cloud machine to add the Rex input to `flake.lock`. Keep the token out
of the repository and command-line arguments. Later, `nix flake update rex`
selects a newer snapshot.
