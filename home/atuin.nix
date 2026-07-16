{ ... }:
{
  programs.atuin = {
    enable = true;
    settings = {
      enter_accept = false;
      keymap_mode = "vim-insert";
      sync.records = true;
    };
  };
}
