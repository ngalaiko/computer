{ pkgs, ... }:
{
  home.packages = [ pkgs.rustup ];

  programs.fish.shellInit = ''
    set --global --export CARGO_HOME "$HOME/.local/share/cargo"
    set --global --export RUSTUP_HOME "$HOME/.local/share/rustup"
    fish_add_path --global --move --path "$CARGO_HOME/bin"
    if test -e "$CARGO_HOME/env.fish"
      source "$CARGO_HOME/env.fish"
    end
  '';
}
