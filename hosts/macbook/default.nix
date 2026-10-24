{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
    ./keyboard.nix
    ./system.nix
    ./docker.nix
    ./homebrew.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.overlays = [ (import ../../overlay.nix { inherit inputs; }) ];
  # Only these unfree packages, here and in pkgs.unstable.
  nixpkgs.config.allowUnfreePredicate =
    p:
    builtins.elem (lib.getName p) [
      "claude-code"
      "amp-cli"
    ];
  system.primaryUser = "nikita";
  system.stateVersion = 6;

  environment.systemPackages = [
    # nix-darwin needs mas on PATH to install masApps
    pkgs.mas
    # Transcripted has no cask/MAS listing; packaged from its release DMG and
    # linked into /Applications/Nix Apps.
    pkgs.transcripted
  ];

  users.users."nikita".home = "/Users/nikita";
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    extraSpecialArgs = { inherit inputs; };
    users."nikita".imports = [
      ../../home
      ./home
    ];
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "nikita"
    ];
    builders-use-substitutes = true;
  };

  # Linux builder VM so this Mac can build the aarch64-linux exedev image; nix
  # offloads *-linux derivations to it (cf. flake.nix's darwinToLinux). Bumped
  # from the 3G / 1-core default for headroom building packages and assembling
  # the image closure. These are runtime qemu flags, so a re-switch is cheap.
  nix.linux-builder = {
    enable = true;
    # qemu user emulation, for the x86_64 exe.dev image.
    systems = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    config.boot.binfmt.emulatedSystems = [ "x86_64-linux" ];
    config.virtualisation = {
      cores = 6;
      # virtualisation.memorySize is derived from this by the darwin-builder
      # profile, so set it here (setting memorySize directly conflicts).
      darwin-builder.memorySize = 8192; # MiB
    };
  };

  programs.fish.enable = true;
}
