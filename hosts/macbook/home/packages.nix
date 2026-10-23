{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # brew-style g-prefixed, so BSD userland stays the default
    coreutils-prefixed
    bun
    dive
    # QMK CLI + full AVR/ARM firmware toolchain, all prebuilt in the binary
    # cache (Homebrew's qmk source-builds ancient gcc@8 from extra taps).
    qmk
    # amp releases often; unstable for a fresher build (cf. claude-code).
    pkgs.unstable.amp-cli
  ];

  programs.claude-code = {
    enable = true;
    # claude-code releases often; pin to unstable for a fresher build (cf. amp-cli).
    package = pkgs.unstable.claude-code;
  };

  programs.codex = {
    enable = true;
    # codex releases often; unstable for a fresher build (cf. claude-code).
    package = pkgs.unstable.codex;
  };
}
