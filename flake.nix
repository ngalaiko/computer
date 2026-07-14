{
  description = "Nix-built OCI image for exe.dev machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
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

      # The system instance: which services are on and which accounts exist.
      exedevFor =
        linuxSystem:
        let
          exedev = import ./modules/exedev { pkgs = nixpkgs.legacyPackages.${linuxSystem}; };
          system = exedev.eval (
            { pkgs, ... }:
            {
              image = {
                name = "computer.exe";
                workingDir = "/home/exedev";
                labels = {
                  "org.opencontainers.image.title" = "computer.exe";
                  "org.opencontainers.image.description" = "exe.dev image: s6-overlay, OpenSSH, and Shelley";
                  # read by exe.dev at VM creation
                  "exe.dev/login-user" = "exedev";
                };
                packages = with pkgs; [
                  bashInteractive
                  coreutils-full
                  findutils
                  gnugrep
                  gnused
                  iproute2
                  procps
                  tzdata
                  util-linux
                ];
              };

              services.sshd = {
                enable = true;
                authorizedKeys.user = "exedev";
              };
              services.shelley = {
                enable = true;
                user = "exedev";
                settings.llm_gateway = "http://169.254.169.254/gateway/llm";
              };

              users.users.exedev = {
                uid = 1000;
                group = "exedev";
                home = "/home/exedev";
                createHome = true;
                shell = "/bin/sh";
                description = "exe.dev user";
              };
              users.groups.exedev.gid = 1000;

              environment.etc.motd.text = ''
                exe.dev image

                This image is built by Nix and includes a PTY-capable login
                environment, OpenSSH, and Shelley.
              '';
            }
          );
        in
        system.build.image;

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
          img = exedevFor (linuxOf system);
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
