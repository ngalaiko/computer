{ ... }:
{
  # brew shellenv: keeps brew-installed tools on PATH.
  programs.fish.shellInit = ''
    set --global --export HOMEBREW_PREFIX "/opt/homebrew"
    set --global --export HOMEBREW_CELLAR "/opt/homebrew/Cellar"
    set --global --export HOMEBREW_REPOSITORY "/opt/homebrew"
    # keep brew after the nix profile so nix-managed tools win on PATH
    fish_add_path --global --move --append --path "/opt/homebrew/bin" "/opt/homebrew/sbin"
    if test -n "$MANPATH[1]"; set --global --export MANPATH ''' $MANPATH; end
    if not contains "/opt/homebrew/share/info" $INFOPATH; set --global --export INFOPATH "/opt/homebrew/share/info" $INFOPATH; end
  '';
}
