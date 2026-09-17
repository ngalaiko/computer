{ lib, ... }:
{
  imports = lib.mapAttrsToList (name: _: ./. + "/${name}") (
    lib.filterAttrs (
      name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
    ) (builtins.readDir ./.)
  );

  # nvim-lspconfig only ships default configs (cmd/root_markers/filetypes) for
  # `vim.lsp.config`; enabling happens per server below via `vim.lsp.enable`.
  programs.nixvim.plugins.lspconfig.enable = true;
}
