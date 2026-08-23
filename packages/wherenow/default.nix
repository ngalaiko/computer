{ pkgs }:

pkgs.buildGoModule {
  pname = "wherenow";
  version = "0.1.0";
  src = ./.;
  vendorHash = "sha256-mGKxBRU5TPgdmiSx0DHEd0Ys8gsVD/YdBfbDdSVpC3U=";
  subPackages = [ "cmd/server" ];
  # Embed the tz database so `--tz Europe/Stockholm` resolves without relying on
  # system zoneinfo files on the target box.
  tags = [ "timetzdata" ];
  # The main package lives in cmd/server, so `go install` names the binary
  # "server"; rename it to the project name.
  postInstall = ''
    mv "$out/bin/server" "$out/bin/wherenow"
  '';
  meta = {
    description = "Self-hosted backend for the Where Now? iOS location app";
    mainProgram = "wherenow";
  };
}
