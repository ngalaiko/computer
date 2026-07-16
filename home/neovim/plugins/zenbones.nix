{ pkgs, ... }:
{
  programs.nixvim = {
    colorscheme = "zenwritten";
    opts.background = "dark";
    extraPlugins = with pkgs.vimPlugins; [
      lush-nvim
      zenbones-nvim
    ];
    highlight = {
      Normal.bg = "none";
      NormalFloat.bg = "none";
    };
  };
}
