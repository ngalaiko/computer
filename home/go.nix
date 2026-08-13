{ pkgs, ... }:
{
  home.packages = [ pkgs.go ];

  programs.fish.shellInit = ''
    set --global --export GOPATH "$HOME/.local/share/go"
    fish_add_path --global --move --path "$GOPATH/bin"
  '';
}
