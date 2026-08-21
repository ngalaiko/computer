# casks and mas apps stay brew (nixpkgs darwin GUI coverage is poor); the
# remaining brews are unfree, tap-only, or missing/broken in nixpkgs. Anything
# not listed here is uninstalled on rebuild (onActivation.cleanup).
{ inputs, ... }:
{
  imports = [ inputs.nix-homebrew.darwinModules.nix-homebrew ];

  # nix-homebrew installs/owns the Homebrew prefix, so the first switch on a
  # fresh Mac bootstraps brew (the nix-darwin `homebrew` block below only
  # manages an existing install). autoMigrate lets it adopt a brew that's
  # already present — e.g. on this machine — instead of erroring.
  nix-homebrew = {
    enable = true;
    user = "nikita";
    autoMigrate = true;
  };

  homebrew = {
    enable = true;

    # brew is fully declarative: unlisted formulae/casks are removed on switch.
    onActivation.cleanup = "uninstall";

    taps = [
      "hamed-elfayome/claude-usage"
      "jsattler/tap"
    ];

    brews = [
      "mole"
      "pi-coding-agent" # pi.dev agent CLI; homebrew-core, no nixpkgs equivalent
      "podman" # nixpkgs podman lacks the machine/vm helpers on darwin
      "vercel" # not in nixpkgs (nodePackages removed); npm tarball needs its own deps
    ];

    casks = [
      "calibre"
      "daisydisk"
      "discord"
      "firefox"
      "ghostty"
      "linear"
      "mullvad-vpn"
      "netnewswire"
      "notion"
      "obsidian"
      "postico@1"
      "raycast"
      "secretive" # Secure Enclave SSH agent (see home/ssh.nix)
      "slack"
      "snapzy"
      "sublime-merge"
      "tailscale-app"
      "telegram"
      "zoom"
      "hamed-elfayome/claude-usage/claude-usage-tracker"
      "jsattler/tap/bettercapture"
    ];

    masApps = {
      "Aeronaut" = 6670275450;
      "Amphetamine" = 937984704;
      "Developer" = 640199958;
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
    };
  };
}
