{ pkgs, ... }:
{
  home.packages = [ pkgs.rustup ];

  programs.fish.shellInit = ''
    fish_add_path --global --move --path "$HOME/.cargo/bin"
    if test -e "$HOME/.cargo/env.fish"
      source "$HOME/.cargo/env.fish"
    end
  '';
}
