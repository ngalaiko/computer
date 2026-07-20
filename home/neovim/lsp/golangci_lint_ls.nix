{ ... }:
{
  programs.nixvim.plugins.lsp.servers.golangci_lint_ls = {
    enable = true;
    extraOptions.init_options.command = [
      "golangci-lint"
      "run"
      "--output.json.path=stdout"
      "--show-stats=false"
      "--issues-exit-code=1"
    ];
  };
}
