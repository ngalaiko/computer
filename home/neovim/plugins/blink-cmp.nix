{ ... }:
{
  programs.nixvim.plugins.blink-cmp = {
    enable = true;
    settings = {
      sources.default = [
        "lsp"
        "path"
        "buffer"
      ];
      completion.menu.draw = {
        cursorline_priority = 0; # disables weird highlight of just completed text
        treesitter = [ ];
      };
      keymap = {
        preset = "enter";
        "<Tab>" = [
          "select_next"
          "fallback"
        ];
        "<S-Tab>" = [
          "select_prev"
          "fallback"
        ];
      };
      appearance.nerd_font_variant = "mono";
    };
  };
}
