{ ... }:
{
  programs.nixvim.plugins.copilot-lua = {
    enable = true;
    settings.suggestion = {
      auto_trigger = true;
      keymap.accept = "<C-a>";
    };
  };
}
