{ pkgs, ... }:
{
  programs.nixvim.extraPlugins = [ pkgs.vimPlugins.vim-ledger ];
}
