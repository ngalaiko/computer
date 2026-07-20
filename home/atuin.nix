{ ... }:
{
  programs.atuin = {
    enable = true;
    flags = [ "--disable-up-arrow" ];
    settings = {
      enter_accept = true;
      keymap_mode = "vim-insert";
      sync.records = true;
    };
  };
}
