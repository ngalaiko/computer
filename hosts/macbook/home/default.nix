{ ... }:
{
  imports = [
    ./brew.nix
    ./docker.nix
    ./fonts
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
