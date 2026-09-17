{ ... }:
{
  programs.nixvim.lsp.servers.html = {
    enable = true;
    config = {
      filetypes = [
        "html"
        "templ"
      ];
      init_options = {
        provideFormatter = true;
        embeddedLanguages = {
          css = true;
          javascript = true;
        };
        configurationSection = [
          "html"
          "css"
          "javascript"
        ];
      };
    };
  };
}
