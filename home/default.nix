{ ... }:
{
  imports = [
    ./atuin.nix
    ./fish
    ./go.nix
    ./jj.nix
    ./neovim
    ./packages.nix
    ./rust.nix
  ];

  home.stateVersion = "25.11";
}
