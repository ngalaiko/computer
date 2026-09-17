{ ... }:
{
  # rustup owns cargo/rustc; only the server itself comes from nix.
  programs.nixvim.lsp.servers.rust_analyzer = {
    enable = true;
    config.settings."rust-analyzer" = {
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
