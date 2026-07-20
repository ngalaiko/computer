{ ... }:
{
  imports = [
    ./atuin.nix
    ./brew.nix
    ./docker.nix
    ./ghostty.nix
    ./jj.nix
    ./ledger.nix
    ./neovim.nix
    ./nix-paths.nix
    ./packages.nix
  ];

  home.file.".hushlogin".text = "";

  programs.fish.interactiveShellInit = "set --global prompt_host macbook";
}
