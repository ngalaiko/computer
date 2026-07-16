{ ... }:
{
  imports = [
    ./brew.nix
    ./ghostty.nix
    ./jj.nix
    ./neovim.nix
    ./nix-paths.nix
    ./packages.nix
  ];

  home.file.".hushlogin".text = "";
}
