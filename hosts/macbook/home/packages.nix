{
  inputs,
  pkgs,
  ...
}:
let
  unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    # claude-code and amp-cli ship under unfree licenses; allow just them, not unfree at large.
    config.allowUnfreePredicate =
      p:
      builtins.elem (pkgs.lib.getName p) [
        "claude-code"
        "amp-cli"
      ];
  };
in
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
    unstable.amp-cli
  ];

  programs.claude-code = {
    enable = true;
    # claude-code releases often; pin to unstable for a fresher build (cf. atuin).
    package = unstable.claude-code;
  };
}
