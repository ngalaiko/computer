{ pkgs, ... }:
{
  programs.mise.enable = true;
  programs.mise.package = pkgs.unstable.mise;
}
