{ inputs, pkgs, ... }:
let
  unstable = import inputs.nixpkgs-unstable { inherit (pkgs.stdenv.hostPlatform) system; };
in
{
  programs.mise.enable = true;
  programs.mise.package = unstable.mise;
}
