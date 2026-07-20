{ pkgs, ... }:
{
  # grammars come from nix, so no ensure_installed/:TSUpdate.
  programs.nixvim.plugins.treesitter = {
    enable = true;
    grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      go
      javascript
      lua
      python
      rust
      sql
      terraform
      typescript
      zig
    ];
    settings = {
      highlight.enable = true;
      indent.enable = true;
    };
  };
}
