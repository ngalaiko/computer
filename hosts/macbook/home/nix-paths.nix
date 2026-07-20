{ ... }:
{
  # brew's fish never sources nix-darwin's /etc/fish init, so wire the nix
  # profiles onto PATH ourselves; runs after brew.nix, so nix bins win.
  programs.fish.shellInit = ''
    fish_add_path --global --move --path \
      "$HOME/.nix-profile/bin" \
      /etc/profiles/per-user/(whoami)/bin \
      /run/current-system/sw/bin \
      /nix/var/nix/profiles/default/bin
  '';
}
