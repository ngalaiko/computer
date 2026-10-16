{ ... }:
{
  imports = [
    ./atuin.nix
    ./brew.nix
    ./docker.nix
    ./fonts
    ./ghostty
    ./jj.nix
    ./ledger.nix
    ./neovim.nix
    ./nix-paths.nix
    ./packages.nix
    ./rex
    ./ssh.nix
  ];

  home.file.".hushlogin".text = "";

  programs.fish.interactiveShellInit = "set --global prompt_host macbook";
}
