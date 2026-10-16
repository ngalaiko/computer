{ pkgs, ... }:
{
  # stable's atuin predates the "history author intent" migration; the local DB
  # was migrated by a newer atuin, so pin this host to unstable.
  programs.atuin.package = pkgs.unstable.atuin;
}
