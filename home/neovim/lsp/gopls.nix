{ ... }:
{
  programs.nixvim.lsp.servers.gopls = {
    enable = true;
    config.settings.gopls = {
      analyses.ST1000 = false; # at least one file in a package should have a package comment
      staticcheck = true;
    };
  };
}
