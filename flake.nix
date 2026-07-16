{
  description = "Nix-built OCI image for exe.dev machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # own nixpkgs pin (no follows): its uv2nix build is tied to it.
    hermes-agent.url = "github:NousResearch/hermes-agent";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      ...
    }:
    let
      lib = nixpkgs.lib;

      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      # darwin builds the matching-arch Linux image via the linux-builder VM.
      darwinToLinux = {
        "aarch64-darwin" = "aarch64-linux";
        "x86_64-darwin" = "x86_64-linux";
      };
      allSystems = linuxSystems ++ builtins.attrNames darwinToLinux;
      linuxOf = system: darwinToLinux.${system} or system;

      imageFor =
        linuxSystem:
        let
          exedev = import ./modules/exedev {
            pkgs = nixpkgs.legacyPackages.${linuxSystem};
            specialArgs = { inherit inputs; };
          };
        in
        (exedev.eval ./hosts/exedev).build.image;

      releaseFor = system: import ./packages/release { pkgs = nixpkgs.legacyPackages.${system}; };
    in
    {
      # This Mac, configured with a Linux builder VM (so it can build *-linux).
      darwinConfigurations.mac = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit inputs; };
        modules = [ ./hosts/mac ];
      };

      # `nix build .#exedev` (current system) or `.#packages.<sys>.exedev`.
      packages = lib.genAttrs allSystems (
        system:
        let
          img = imageFor (linuxOf system);
        in
        {
          exedev = img;
          default = img;
        }
        // releaseFor system
      );

      devShells = lib.genAttrs allSystems (system: {
        default =
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in
          pkgs.mkShell {
            packages = [
              pkgs.gh
              pkgs.gitMinimal
              pkgs.regctl
              pkgs.jujutsu
              pkgs.skopeo
            ]
            ++ lib.attrValues (releaseFor system);
          };
      });

      formatter = lib.genAttrs allSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
