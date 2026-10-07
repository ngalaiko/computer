# casks and mas apps stay brew (nixpkgs darwin GUI coverage is poor); the
# remaining brews are unfree, tap-only, or missing/broken in nixpkgs. Anything
# not listed here is uninstalled on rebuild (onActivation.cleanup).
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  names = map (x: x.name);
  qualified = xs: lib.filter (lib.hasInfix "/") (names xs);

  # newer Homebrew (HOMEBREW_REQUIRE_TAP_TRUST) refuses casks/formulae from
  # third-party taps unless trusted. Derived from the declared taps and
  # tap-qualified casks/brews, so declaring a tap is enough.
  trust = pkgs.writeText "homebrew-trust.json" (
    builtins.toJSON {
      trustedtaps = names config.homebrew.taps;
      trustedcasks = qualified config.homebrew.casks;
      trustedformulae = qualified config.homebrew.brews;
    }
  );
in
{
  imports = [ inputs.nix-homebrew.darwinModules.nix-homebrew ];

  # trust.json lives outside nix, so write it declaratively each activation.
  # Runs after the brew-bundle step, so it persists the file for subsequent
  # switches.
  home-manager.users."nikita" =
    { config, lib, ... }:
    {
      home.activation.homebrewTrust = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run install -Dm600 ${trust} ${config.home.homeDirectory}/.homebrew/trust.json
      '';
    };

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

    onActivation = {
      # brew is fully declarative: unlisted formulae/casks are removed on switch.
      cleanup = "uninstall";
    };

    taps = [
      "jsattler/tap"
    ];

    brews = [
      "mole"
      "pi-coding-agent" # pi.dev agent CLI; homebrew-core, no nixpkgs equivalent
      "podman" # nixpkgs podman lacks the machine/vm helpers on darwin
    ];

    casks = [
      "amp-app" # ampcode.com coding agent app
      "calibre"
      "chatgpt" # OpenAI's desktop app; hosts Codex since the standalone Codex app was discontinued (2026-07)
      "daisydisk"
      "firefox"
      "ghostty@tip" # tip build
      "little-snitch"
      "mullvad-vpn"
      "netnewswire"
      "obsidian"
      "postico@1"
      "raycast"
      "secretive" # Secure Enclave SSH agent (see home/ssh.nix)
      "sublime-merge"
      "tailscale-app"
      "telegram"
      "zoom"
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
      "Xcode" = 497799835;
    };
  };
}
