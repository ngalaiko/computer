{ ... }:
{
  # cmd is `cue lsp`; the cue binary is provided via conform.nix's extraPackages.
  programs.nixvim.lsp.servers.cue.enable = true;
}
