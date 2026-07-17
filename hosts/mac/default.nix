{ inputs, pkgs, ... }:
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
    ./defaults.nix
    ./homebrew.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.primaryUser = "nikita.galaiko";
  system.stateVersion = 6;

  # nix-darwin needs mas on PATH to install masApps
  environment.systemPackages = [ pkgs.mas ];

  users.users."nikita.galaiko".home = "/Users/nikita.galaiko";
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    users."nikita.galaiko".imports = [
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
      "nikita.galaiko"
    ];
    builders-use-substitutes = true;
  };

  programs.fish.enable = true;
}
