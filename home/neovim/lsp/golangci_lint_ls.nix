{ ... }:
{
  programs.nixvim.lsp.servers.golangci_lint_ls = {
    enable = true;
    config.init_options.command = [
      "golangci-lint"
      "run"
      "--output.json.path=stdout"
      "--show-stats=false"
      "--issues-exit-code=1"
    ];
  };
}
