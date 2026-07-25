{ pkgs, inputs, ... }:
let
  # open-terminal isn't in nixpkgs; we package it from its PyPI wheel, built
  # against unstable's python3Packages (dep floors exceed nixpkgs-25.11).
  unstable = import ../../../packages/unstable.nix { inherit inputs pkgs; };
in
{
  services.open-terminal = {
    enable = true;
    package = import ../../../packages/open-terminal { pkgs = unstable; };
  };

  # Tools the agent-driven shell gets on its PATH. The account is unprivileged
  # (no sudo, not nix-trusted), which caps what a connected model can do.
  users.users.open-terminal.packages = with pkgs; [
    git
    jq
    ripgrep
    curl
    coreutils
    uv
  ];

  services.backup = {
    enable = true;
    # agent workspace + the API key open-webui is paired with.
    paths = [ "/var/lib/open-terminal" ];
  };
}
