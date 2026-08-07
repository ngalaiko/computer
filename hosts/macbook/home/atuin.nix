{ inputs, pkgs, ... }:
let
  unstable = import inputs.nixpkgs-unstable { inherit (pkgs.stdenv.hostPlatform) system; };
in
{
  # stable's atuin predates the "history author intent" migration; the local DB
  # was migrated by a newer atuin, so pin this host to unstable.
  programs.atuin.package = unstable.atuin;
}
