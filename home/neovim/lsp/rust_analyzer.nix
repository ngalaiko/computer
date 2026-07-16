{ ... }:
{
  programs.nixvim.plugins.lsp.servers.rust_analyzer = {
    enable = true;
    # rustup owns the toolchain
    installCargo = false;
    installRustc = false;
    settings = {
      assist.importPrefix = "by_self";
      cargo = {
        loadOutDirsFromCheck = true;
        features = "all";
        buildScripts.enable = false;
      };
      check.features = "all";
      procMacro.enable = true;
      checkOnSave = true;
    };
  };
}
