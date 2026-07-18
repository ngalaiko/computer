{ ... }:
{
  programs.atuin = {
    enable = true;
    settings = {
      enter_accept = true;
      keymap_mode = "vim-insert";
      sync.records = true;
    };
  };
}
