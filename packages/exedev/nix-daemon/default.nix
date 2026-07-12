# Nix, so `nix` works on the VM (its nix-daemon service lives in s6-overlay).
{ pkgs }:
{
  packages = [ pkgs.nix ];
}
