{ ... }:
{
  # XDG base dirs — define with the spec defaults if the session hasn't.
  programs.fish.shellInit = ''
    set --query XDG_CONFIG_HOME; or set --global --export XDG_CONFIG_HOME "$HOME/.config"
    set --query XDG_CACHE_HOME;  or set --global --export XDG_CACHE_HOME "$HOME/.cache"
    set --query XDG_DATA_HOME;   or set --global --export XDG_DATA_HOME "$HOME/.local/share"
    set --query XDG_STATE_HOME;  or set --global --export XDG_STATE_HOME "$HOME/.local/state"
  '';
}
