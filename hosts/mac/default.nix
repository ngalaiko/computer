{ ... }:
{
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.primaryUser = "nikita.galaiko";
  system.stateVersion = 6;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "nikita.galaiko"
    ];
  };

  programs.fish.enable = true;

  nix.linux-builder = {
    enable = true;
    ephemeral = true;
    maxJobs = 4;
    systems = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    config = {
      virtualisation = {
        cores = 6;
        darwin-builder = {
          diskSize = 40 * 1024; # MiB
          memorySize = 8 * 1024; # MiB
        };
      };
      boot.binfmt.emulatedSystems = [ "x86_64-linux" ];
    };
  };
}
