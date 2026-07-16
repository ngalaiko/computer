{ inputs, ... }:
{
  imports = [
    inputs.nixvim.homeModules.nixvim
    ./options.nix
    ./keymaps.nix
    ./plugins
    ./lsp
  ];

  programs.nixvim = {
    enable = true;
    defaultEditor = true;
  };
}
