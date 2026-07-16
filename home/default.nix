{ ... }:
{
  imports = [
    ./atuin.nix
    ./fish
    ./jj.nix
    ./neovim
  ];

  home.stateVersion = "25.11";
}
