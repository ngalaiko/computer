{
  config,
  lib,
  pkgs,
  ...
}:
let
  # newer Homebrew (HOMEBREW_REQUIRE_TAP_TRUST) refuses casks/formulae from
  # third-party taps unless trusted; trust.json lives outside nix, so write it
  # declaratively each activation. Runs after the brew-bundle step, so it
  # persists the file for subsequent switches.
  trust = pkgs.writeText "homebrew-trust.json" (
    builtins.toJSON {
      trustedtaps = [
        "hamed-elfayome/claude-usage"
        "jsattler/tap"
      ];
      trustedcasks = [
        "hamed-elfayome/claude-usage/claude-usage-tracker"
        "jsattler/tap/bettercapture"
      ];
      trustedformulae = [ ];
    }
  );
in
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

  home.activation.homebrewTrust = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run install -Dm600 ${trust} ${config.home.homeDirectory}/.homebrew/trust.json
  '';
}
