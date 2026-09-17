{ lib, ... }:
{
  programs.nixvim = {
    plugins.mini = {
      # neo-tree's icon provider pcall-requires "nvim-web-devicons"; the mock
      # registers MiniIcons under that name.
      mockDevIcons = true;
      modules.icons = { };
    };

    # mini.icons has no color switch; its groups link to Function/Diagnostic*.
    # Override (not `highlight`) because `:colorscheme` clears the earlier pass.
    highlightOverride =
      lib.genAttrs
        (map (n: "MiniIcons${n}") [
          "Azure"
          "Blue"
          "Cyan"
          "Green"
          "Grey"
          "Orange"
          "Purple"
          "Red"
          "Yellow"
        ])
        (_: {
          link = "Normal";
        });
  };
}
