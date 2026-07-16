# casks and mas apps stay brew (nixpkgs darwin GUI coverage is poor); the
# few remaining brews are unfree, tap-only, or missing/broken in nixpkgs.
{ ... }:
{
  homebrew = {
    enable = true;

    taps = [
      "hamed-elfayome/claude-usage"
      "jsattler/tap"
    ];

    brews = [
      "mole"
      "podman" # nixpkgs podman lacks the machine/vm helpers on darwin
    ];

    casks = [
      "jsattler/tap/bettercapture"
      "calibre"
      "hamed-elfayome/claude-usage/claude-usage-tracker"
      "ghostty"
      "mullvad-vpn"
      "netnewswire"
      "postico@1"
      "raycast"
      "sublime-merge"
      "tailscale-app"
      "telegram"
      "zoom"
    ];

    masApps = {
      "1Password for Safari" = 1569813296;
      "Aeronaut" = 6670275450;
      "Amphetamine" = 937984704;
      "Developer" = 640199958;
      "Emcee for Music" = 408774844;
      "Kagi for Safari" = 1622835804;
      "NextDNS" = 1464122853;
      "Numbers" = 361304891;
      "Obsidian Web Clipper" = 6720708363;
      "Page Screenshot for Safari" = 1472715727;
      "Pages" = 361309726;
      "Strongbox" = 897283731;
      "Sweet Home 3D" = 669289700;
      "TestFlight" = 899247664;
      "The Unarchiver" = 425424353;
      "Translate for Safari" = 1445040281;
      "Windows App" = 1295203466;
      "Xcode" = 497799835;
    };
  };
}
