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
    pricehist
    tree
    typst
    uv
    xq-xml
    yq-go
  ];
}
