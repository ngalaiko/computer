{ inputs, ... }:
{
  imports = [
    inputs.nixvim.homeModules.nixvim
    ./options.nix
    ./keymaps.nix
    ./plugins
    ./lsp
  ];

  programs.nixvim = {
    enable = true;
    defaultEditor = true;

    # remote-plugin providers; no plugin here is a remote plugin, and the ruby
    # one drags ruby + a full clang/llvm toolchain (~2.8G) as a runtime dep.
    withRuby = false;
    withPython3 = false;
    withNodeJs = false;
    withPerl = false;
  };
}
