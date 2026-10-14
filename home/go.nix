{ config, ... }:
let
  goPath = "${config.home.homeDirectory}/.local/share/go";
in
{
  programs.go = {
    enable = true;
    env.GOPATH = goPath;
  };

  programs.fish.shellInit = ''
    fish_add_path --global --move --path "${goPath}/bin"
  '';
}
