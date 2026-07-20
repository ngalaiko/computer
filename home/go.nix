{ pkgs, ... }:
{
  home.packages = [ pkgs.go ];

  programs.fish.shellInit = ''
    set --global --export GOPATH "$HOME/go"
    fish_add_path --global --move --path "$GOPATH/bin"
  '';
}
