{ inputs, pkgs, ... }:
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
    ./defaults.nix
    ./homebrew.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.primaryUser = "nikita";
  system.stateVersion = 6;

  # nix-darwin needs mas on PATH to install masApps
  environment.systemPackages = [ pkgs.mas ];

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

  programs.fish.enable = true;
}
