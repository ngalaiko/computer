{ pkgs, ... }:
let
  # rg skips hidden files, which the git tool it replaces in <C-g> did not.
  ripgreprc = pkgs.writeText "ripgreprc" ''
    --hidden
    --glob=!.git/
    --glob=!.jj/
  '';
in
{
  # mini.pick shells out to these; nvim must find them regardless of PATH.
  programs.nixvim.extraPackages = with pkgs; [
    jujutsu
    ripgrep
  ];

  # scoped to nvim; leaves rg in the shell alone
  programs.nixvim.extraConfigLua = ''
    vim.env.RIPGREP_CONFIG_PATH = "${ripgreprc}"
  '';

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
