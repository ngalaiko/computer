{ ... }:
{
  programs.nixvim.plugins.lsp.servers.gopls = {
    enable = true;
    settings.gopls = {
      analyses.ST1000 = false; # at least one file in a package should have a package comment
      staticcheck = true;
    };
  };
}
