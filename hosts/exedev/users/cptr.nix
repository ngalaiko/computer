{ pkgs, inputs, ... }:
let
  # cptr isn't in nixpkgs; we package it from its PyPI wheel, built against
  # unstable's python3Packages (its dep floors exceed nixpkgs-25.11). It ships
  # under the unfree "Open Use License" (ELv2 + attribution), so allow just it.
  unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfreePredicate = p: pkgs.lib.getName p == "cptr";
  };
in
{
  services.cptr = {
    enable = true;
    package = import ../../../packages/cptr { pkgs = unstable; };
  };

  # cptr's terminal + git features shell out to these; on the cptr user's PATH.
  # The account is unprivileged (no sudo, not nix-trusted), which caps what a
  # signed-in user can do on the box.
  users.users.cptr.packages = with pkgs; [
    git
    gh
    jq
    ripgrep
    curl
    coreutils
    uv
    # pydub (cptr audio) shells out to ffmpeg/ffprobe; headless = no X/GUI closure.
    ffmpeg-headless
  ];

  services.backup = {
    enable = true;
    # cptr's admin account, db, and workspaces live here.
    paths = [ "/var/lib/cptr" ];
  };
}
