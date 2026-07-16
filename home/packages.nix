{ pkgs, ... }:
{
  home.packages = with pkgs; [
    flyctl
    gh
    git
    git-lfs
    jq
    ledger
    pricehist
    tree
    typst
    uv
    xq-xml
    yq-go
  ];
}
