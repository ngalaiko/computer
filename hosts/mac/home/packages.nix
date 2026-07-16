{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # brew-style g-prefixed, so BSD userland stays the default
    coreutils-prefixed
  ];
}
