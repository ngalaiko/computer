{ pkgs, ... }:
{
  home.packages = [ pkgs.go ];

  # /opt/go is the pre-existing mac GOPATH; go's default elsewhere.
  programs.fish.shellInit = ''
    if test -d /opt/go
      set --global --export GOPATH "/opt/go"
    else
      set --global --export GOPATH "$HOME/go"
    end
    fish_add_path --global --move --path "$GOPATH/bin"
  '';
}
