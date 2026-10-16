# NixOS on an exe.dev VM: the provider owns the kernel and DNS, NixOS owns the
# rest, with systemd as PID 1.
{
  imports = [
    ./backup.nix
    ./image.nix
    ./ingress.nix
  ];
}
