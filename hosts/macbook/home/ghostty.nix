{ config, ... }:
{
  programs.ghostty = {
    enable = true;
    # the app comes from brew; config only
    package = null;
    settings = {
      command = "/etc/profiles/per-user/${config.home.username}/bin/fish";
      keybind = [
        "ctrl+alt+s=new_split:down"
        "ctrl+alt+v=new_split:right"
        "ctrl+shift+h=goto_split:left"
        "ctrl+shift+j=goto_split:down"
        "ctrl+shift+k=goto_split:up"
        "ctrl+shift+l=goto_split:right"
        "super+t=new_tab"
        "super+w=close_surface"
        "ctrl+alt+l=next_tab"
        "ctrl+alt+h=previous_tab"
        "super+physical:one=goto_tab:1"
        "super+physical:two=goto_tab:2"
        "super+physical:three=goto_tab:3"
        "super+physical:four=goto_tab:4"
        "super+physical:five=goto_tab:5"
        "super+physical:six=goto_tab:6"
        "super+physical:seven=goto_tab:7"
        "super+physical:eight=goto_tab:8"
        "super+physical:nine=goto_tab:9"
        "super+plus=increase_font_size:1"
        "super+equal=increase_font_size:1"
        "super+minus=decrease_font_size:1"
        "super+zero=reset_font_size"
      ];
      macos-titlebar-style = "tabs";
      cursor-style = "underline";
      cursor-style-blink = true;
      font-size = 13;
      font-family = "Berkeley Mono";
      theme = "zenwritten_dark";
    };
  };

  xdg.configFile."ghostty/themes/zenwritten_dark".source = ./ghostty/zenwritten_dark;
}
