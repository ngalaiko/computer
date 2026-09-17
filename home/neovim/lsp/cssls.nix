{ ... }:
{
  programs.nixvim.lsp.servers.cssls = {
    enable = true;
    config = {
      init_options.provideFormatter = true;
      settings = {
        css.validate = true;
        scss.validate = true;
        less.validate = true;
      };
    };
  };
}
