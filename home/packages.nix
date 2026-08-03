{ pkgs, ... }:
{
  home.packages = with pkgs; [
    flyctl
    gettext
    gh
    gitMinimal
    git-lfs
    jq
    ledger
    ncdu
    pricehist
    tree
    typst
    uv
    xq-xml
    yq-go
  ];
}
