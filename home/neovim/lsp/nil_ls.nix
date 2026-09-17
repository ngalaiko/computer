{ ... }:
{
  # nixd is the alternative: it adds eval-based completion of module options,
  # but needs a per-project expr pointing at the flake to be worth it.
  # Formatting stays with conform (nixfmt), matching treefmt.nix.
  programs.nixvim.lsp.servers.nil_ls.enable = true;
}
