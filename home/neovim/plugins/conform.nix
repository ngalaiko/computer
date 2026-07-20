{ pkgs, ... }:
{
  programs.nixvim = {
    plugins.conform-nvim = {
      enable = true;
      settings.formatters_by_ft = {
        lua = [ "stylua" ];
        javascript = [ "prettierd" ];
        javascriptreact = [ "prettierd" ];
        typescript = [ "prettierd" ];
        typescriptreact = [ "prettierd" ];
        go = [ "golangci-lint" ];
        python = [ "ruff_format" ];
        rust = [ "rustfmt" ];
      };
    };

    # ruff comes with the lsp server; rustfmt (rustup's) resolves from PATH.
    extraPackages = with pkgs; [
      stylua
      prettierd
      golangci-lint
    ];
  };
}
