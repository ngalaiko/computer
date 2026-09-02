{ config, ... }:
{
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/AGENTS.md";
}
