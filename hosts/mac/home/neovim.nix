{ pkgs, ... }:
{
  programs.nixvim = {
    # upstream `make` compiles a swift helper into ~/.local/bin and loads it
    # as a LaunchAgent; that part stays imperative (rerun on a fresh mac).
    extraPlugins = [
      (pkgs.vimUtils.buildVimPlugin {
        pname = "ghostty-navigator.nvim";
        version = "2026-03-09";
        src = pkgs.fetchFromGitHub {
          owner = "tmm";
          repo = "ghostty-navigator.nvim";
          rev = "7806a5f315bcafaa16386acd4bd648b1dff25dc5";
          hash = "sha256-J3pdtmuhb6ik8FXneMY1K0dbkxadvi+WC/noGB1cXoQ=";
        };
      })
    ];
    extraConfigLua = ''require("ghostty-navigator").setup({})'';

    # terraform tooling is mac-only; trivy alone is ~266M and unused remotely.
    plugins.lsp.servers.terraformls.enable = true;
    plugins.lint = {
      enable = true;
      lintersByFt = {
        terraform = [
          "tflint"
          "trivy"
        ];
        terraform-vars = [
          "tflint"
          "trivy"
        ];
      };
    };
    extraPackages = with pkgs; [
      tflint
      trivy
    ];
  };
}
