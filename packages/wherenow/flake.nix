{
  description = "wherenow — self-hosted backend for the Where Now? iOS location app";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          wherenow = pkgs.buildGoModule {
            pname = "wherenow";
            version = "0.1.0";
            src = ./.;
            vendorHash = "sha256-mGKxBRU5TPgdmiSx0DHEd0Ys8gsVD/YdBfbDdSVpC3U=";
            subPackages = [ "cmd/server" ];
            # embed the tz database so `--tz Europe/Stockholm` resolves without
            # relying on system zoneinfo files on the target box.
            tags = [ "timetzdata" ];
            # the main package lives in cmd/server, so `go install` names the
            # binary "server"; rename it to the project name.
            postInstall = ''
              mv "$out/bin/server" "$out/bin/wherenow"
            '';
            meta = {
              description = "Self-hosted backend for the Where Now? iOS location app";
              mainProgram = "wherenow";
            };
          };
          default = wherenow;
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
