{ inputs, pkgs, ... }:
let
  unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    # claude-code ships under an unfree license; allow just it, not unfree at large.
    config.allowUnfreePredicate = p: pkgs.lib.getName p == "claude-code";
  };
in
{
  home.packages = with pkgs; [
    # brew-style g-prefixed, so BSD userland stays the default
    coreutils-prefixed
    dive
    # QMK CLI + full AVR/ARM firmware toolchain, all prebuilt in the binary
    # cache (Homebrew's qmk source-builds ancient gcc@8 from extra taps).
    qmk
    # claude-code releases often; pin to unstable for a fresher build (cf. atuin).
    unstable.claude-code
  ];
}
