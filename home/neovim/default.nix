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

    # Build nixvim against our own (follows-unified) nixpkgs — the same instance
    # it already uses via the flake's `inputs.nixvim.inputs.nixpkgs.follows`.
    # Stating it explicitly (above default priority) just acknowledges that
    # choice, so nixvim stops warning that its default source was affected by the
    # follows. No rebuild: same nixpkgs, only now declared on purpose.
    nixpkgs.source = inputs.nixpkgs;

    # remote-plugin providers; no plugin here is a remote plugin, and the ruby
    # one drags ruby + a full clang/llvm toolchain (~2.8G) as a runtime dep.
    withRuby = false;
    withPython3 = false;
    withNodeJs = false;
    withPerl = false;
  };
}
