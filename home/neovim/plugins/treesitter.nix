{ pkgs, ... }:
{
  # grammars come from nix, so no ensure_installed/:TSUpdate.
  # markdown, lua, vim(doc), c and query ship with neovim itself.
  programs.nixvim.plugins.treesitter = {
    enable = true;
    grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      bash
      css
      cue
      dockerfile
      fish
      go
      html
      javascript
      json
      ledger
      lua
      nix
      python
      rust
      sql
      svelte
      templ
      terraform
      toml
      tsx
      typescript
      yaml
      zig
    ];
    settings = {
      highlight.enable = true;
      indent.enable = true;
    };
  };
}
