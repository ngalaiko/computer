{ ... }:
{
  imports = [
    ./atuin.nix
    ./fish
    ./jj.nix
    ./neovim
    ./packages.nix
  ];

  home.stateVersion = "25.11";
}
