{
  description = "Nix-built OCI image for exe.dev machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # stable's atuin is older than the one that migrated the local atuin DB, so
    # atuin (and other fast-moving tools) pin unstable — see
    # hosts/macbook/home/atuin.nix and packages/unstable.nix.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "github:nix-community/nixvim/nixos-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # my pi ⇄ Telegram gateway (the assistant's bridge). Deliberately does NOT
    # follow our nixpkgs, even though both track 26.05: it's a hermetic flake
    # whose node_modules is a fixed-output derivation pinned to its own nixpkgs'
    # bun, and repinning bun (even across 26.05 revs) would break that hash.
    pilegram.url = "github:ngalaiko/pilegram";
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

      configFor =
        linuxSystem:
        (import ./modules/exedev {
          pkgs = nixpkgs.legacyPackages.${linuxSystem};
          specialArgs = { inherit inputs; };
        }).eval
          ./hosts/exedev;

      releaseFor = system: import ./packages/release { pkgs = nixpkgs.legacyPackages.${system}; };
    in
    {
      # This Mac, configured with a Linux builder VM (so it can build *-linux).
      darwinConfigurations.macbook = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit inputs; };
        modules = [ ./hosts/macbook ];
      };

      # `nix build .#exedev` (base image) or `.#system` (the in-place generation);
      # `.#packages.<sys>.{exedev,system}` for a specific arch.
      packages = lib.genAttrs allSystems (
        system:
        let
          cfg = configFor (linuxOf system);
        in
        {
          exedev = cfg.build.image;
          system = cfg.build.system;
          default = cfg.build.image;
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

      formatter = lib.genAttrs allSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
