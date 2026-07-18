{ pkgs, ... }:
{
  programs.nixvim = {
    # split nav is handled by ghostty `performable:goto_split` keybinds +
    # the <C-hjkl> -> <C-w>hjkl maps in home/neovim/keymaps.nix (no daemon).

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
