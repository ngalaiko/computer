{
  description = "NixOS for exe.dev machines and nix-darwin for the Mac";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
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
    # Installs and owns the Homebrew prefix itself, so a fresh Mac doesn't need
    # brew pre-installed — the first darwin-rebuild switch bootstraps it. The
    # nix-darwin `homebrew` module only manages an already-installed brew.
    # (No nixpkgs input to follow; it pins Homebrew/brew via its own brew-src.)
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    # One `nix fmt` / `nix flake check` gate over the whole tree (nix, python,
    # shell, yaml) instead of nix-only. Config lives in ./treefmt.nix.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # encore binaries
    encore = {
      url = "github:encoredev/encore-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # dash0 cli
    dash0-cli = {
      url = "github:dash0hq/dash0-cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # sqlite-backed shell history (atuin replacement)
    stinkpot = {
      url = "git+https://tangled.org/oppi.li/stinkpot";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mattpocock-skills = {
      url = "github:mattpocock/skills/49dd158d1076134a641b33efb035946536778336";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      ...
    }:
    let
      inherit (nixpkgs) lib;

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

      exedevFor =
        linuxSystem:
        self.lib.exedevFor {
          system = linuxSystem;
        };

      releaseFor = system: import ./scripts { pkgs = nixpkgs.legacyPackages.${system}; };

      # Repo packages available on `system`.
      repoPackagesFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system}.extend self.overlays.default;
        in
        lib.filterAttrs (_: lib.meta.availableOn pkgs.stdenv.hostPlatform) {
          inherit (pkgs)
            obsidian-headless
            transcripted
            vault-sync
            wherenow
            ;
        };

      treefmtFor =
        system: inputs.treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} ./treefmt.nix;
    in
    {
      overlays.default = import ./overlay.nix { inherit inputs; };

      lib = {
        exedevFor =
          {
            system ? "x86_64-linux",
            extraInputs ? { },
            extraModules ? [ ],
          }:
          nixpkgs.lib.nixosSystem {
            specialArgs.inputs = inputs // extraInputs;
            modules = [
              ./hosts/exedev
              { nixpkgs.hostPlatform = system; }
            ]
            ++ extraModules;
          };
        macbookFor =
          {
            extraInputs ? { },
            extraModules ? [ ],
          }:
          nix-darwin.lib.darwinSystem {
            specialArgs.inputs = inputs // extraInputs;
            modules = [ ./hosts/macbook ] ++ extraModules;
          };
      };

      # Public base configurations; private integrations live in host flakes.
      nixosConfigurations.exedev = exedevFor "x86_64-linux";
      darwinConfigurations.macbook = self.lib.macbookFor { };

      # `nix build .#exedev` (base image); `.#packages.<sys>.exedev` for a
      # specific arch.
      packages = lib.genAttrs allSystems (
        system:
        let
          cfg = (exedevFor (linuxOf system)).config;
        in
        {
          exedev = cfg.system.build.ociImage;
          default = cfg.system.build.ociImage;
        }
        // releaseFor system
        // repoPackagesFor system
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

      formatter = lib.genAttrs allSystems (system: (treefmtFor system).config.build.wrapper);

      # `nix flake check` fails if the tree isn't treefmt-clean. CI relies on this
      # instead of a bespoke `nix fmt && git diff` step.
      checks = lib.genAttrs allSystems (system: {
        backup-dependencies = import ./modules/nixos/exedev/backup-dependencies-test.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit ((exedevFor (linuxOf system))) config;
        };
        backup-restore = import ./modules/nixos/exedev/backup-test.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          script = (exedevFor (linuxOf system)).config.systemd.services.backup-restore.script;
          sourceRestic = "${nixpkgs.legacyPackages.${linuxOf system}.restic}/bin/restic";
        };
        formatting = (treefmtFor system).config.build.check self;
        pi-search =
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in
          pkgs.runCommand "pi-search" { nativeBuildInputs = [ pkgs.python3 ]; } ''
            PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s ${./home/agents/pi/skills/web-search}
            touch $out
          '';
        pi-command-guards =
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in
          pkgs.runCommand "pi-command-guards" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
            node --experimental-strip-types --test ${./home/agents/pi}/command-guards.test.mjs
            touch $out
          '';
      });
    };
}
