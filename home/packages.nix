{ pkgs, ... }:
{
  home.packages = with pkgs; [
    gh
    git
    git-lfs
    jq
    ledger
    tree
    typst
    xq-xml
    yq-go
  ];
}
