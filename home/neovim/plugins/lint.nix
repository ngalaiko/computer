{ pkgs, ... }:
{
  programs.nixvim = {
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
