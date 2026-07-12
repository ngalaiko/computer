{
  description = "Nix-built OCI image for exe.dev machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    # Provides docker.nix (the nixos/nix bootstrap image builder).
    nixSource = {
      url = "github:NixOS/nix/2.31.5";
      flake = false;
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixSource,
      nix-darwin,
    }:
    let
      lib = nixpkgs.lib;

      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      # darwin maps to the matching-arch Linux image so `nix build` works on a
      # Mac (offloaded to the linux-builder VM).
      darwinToLinux = {
        "aarch64-darwin" = "aarch64-linux";
        "x86_64-darwin" = "x86_64-linux";
      };
      allSystems = linuxSystems ++ builtins.attrNames darwinToLinux;
      linuxOf = system: darwinToLinux.${system} or system;

      exedevFor =
        linuxSystem:
        import ./packages/exedev {
          pkgs = nixpkgs.legacyPackages.${linuxSystem};
          inherit nixSource;
        };
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
          img = exedevFor (linuxOf system);
        in
        {
          exedev = img;
          default = img;
        }
      );

      formatter = lib.genAttrs allSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
