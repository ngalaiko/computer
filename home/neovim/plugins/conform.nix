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
        terraform = [ "terraform_fmt" ];
        terraform-vars = [ "terraform_fmt" ];
        sql = [ "sqlfmt" ];
        rust = [ "rustfmt" ];
      };
    };

    # ruff comes with the lsp server; terraform (unfree), rustfmt (rustup's),
    # sqlfmt (unpackaged)
    extraPackages = with pkgs; [
      stylua
      prettierd
      golangci-lint
    ];
  };
}
