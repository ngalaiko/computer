{ ... }:
{
  programs.nixvim.plugins.mini = {
    enable = true;
    modules = {
      diff = {
        source.__raw = ''{ require("mini.diff").gen_source.git() }'';
        view = {
          style = "sign";
          signs = {
            add = "▎";
            change = "▎";
            delete = "";
          };
        };
      };
      pick = { };
    };
  };
}
