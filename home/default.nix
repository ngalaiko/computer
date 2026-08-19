{ inputs, pkgs, ... }:
{
  imports = [
    ./agents
    ./atuin.nix
    ./fish
    ./go.nix
    ./jj.nix
    ./mise.nix
    ./neovim
    ./packages.nix
    ./rust.nix
    ./xdg.nix
    ./encore.nix
    inputs.encore.homeModules.default
  ];

  # session vars point LOCALE_ARCHIVE at i18n.glibcLocales; the default
  # all-locales archive is 232 MB in the image, en_US.UTF-8 alone a few MB.
  i18n.glibcLocales = pkgs.glibcLocales.override {
    allLocales = false;
    locales = [ "en_US.UTF-8/UTF-8" ];
  };

  home.stateVersion = "25.11";
}
