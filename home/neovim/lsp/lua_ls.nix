{ ... }:
{
  programs.nixvim.lsp.servers.lua_ls = {
    enable = true;
    # settings go to the server verbatim, so the `Lua` section is explicit here
    config.settings.Lua = {
      diagnostics.globals = [ "vim" ];
      workspace.library.__raw = ''vim.api.nvim_get_runtime_file("", true)'';
    };
  };
}
