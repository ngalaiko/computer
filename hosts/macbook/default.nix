{ inputs, pkgs, ... }:
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
    ./keyboard.nix
    ./system.nix
    ./docker.nix
    ./homebrew.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.primaryUser = "nikita";
  system.stateVersion = 6;

  environment.systemPackages = [
    # nix-darwin needs mas on PATH to install masApps
    pkgs.mas
    # Transcripted has no cask/MAS listing; packaged from its release DMG and
    # linked into /Applications/Nix Apps.
    (import ../../packages/transcripted { inherit pkgs; })
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
    config.virtualisation = {
      cores = 6;
      # virtualisation.memorySize is derived from this by the darwin-builder
      # profile, so set it here (setting memorySize directly conflicts).
      darwin-builder.memorySize = 8192; # MiB
    };
  };

  programs.fish.enable = true;
}
