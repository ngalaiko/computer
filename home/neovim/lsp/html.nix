{ ... }:
{
  programs.nixvim.plugins.lsp.servers.html = {
    enable = true;
    filetypes = [
      "html"
      "templ"
    ];
    extraOptions.init_options = {
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
}
