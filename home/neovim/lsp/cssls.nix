{ ... }:
{
  programs.nixvim.plugins.lsp.servers.cssls = {
    enable = true;
    extraOptions.init_options.provideFormatter = true;
    settings = {
      css.validate = true;
      scss.validate = true;
      less.validate = true;
    };
  };
}
