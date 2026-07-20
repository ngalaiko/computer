{ pkgs, ... }:
{
  home.packages = with pkgs; [
    flyctl
    gh
    # gitMinimal: full git pulls git-p4 -> python3 -> a clang/llvm toolchain
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
