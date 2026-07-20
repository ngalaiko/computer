{ ... }:
{
  programs.nixvim.plugins.lsp.servers.lua_ls = {
    enable = true;
    # nixvim wraps these under the lspconfig section itself
    settings = {
      diagnostics.globals = [ "vim" ];
      workspace.library.__raw = ''vim.api.nvim_get_runtime_file("", true)'';
    };
  };
}
