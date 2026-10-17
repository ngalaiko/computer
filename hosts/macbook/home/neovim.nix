{ pkgs, ... }:
{
  programs.nixvim = {
    # terraform tooling is mac-only; trivy alone is ~266M and unused remotely.
    lsp.servers.terraformls.enable = true;
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
