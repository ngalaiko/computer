{ ... }:
{
  programs.nixvim.plugins.neo-tree = {
    enable = true;
    settings = {
      close_if_last_window = true;
      enable_git_status = false;
      enable_diagnostics = false;
      open_files_do_not_replace_types = [ "trouble" ];
      default_component_configs = {
        indent = {
          highlight = "";
          expander_highlight = "";
        };
        icon.highlight = "";
        modified.highlight = "";
        name.highlight = "";
      };
      filesystem = {
        filtered_items = {
          visible = false;
          hide_dotfiles = false;
          hide_gitignored = true;
        };
        group_empty_dirs = true;
        use_libuv_file_watcher = true;
      };
      window.mappings."/" = "";
    };
  };
}
