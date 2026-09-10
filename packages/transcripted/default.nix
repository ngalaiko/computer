{ pkgs }:

# No Homebrew cask or Mac App Store listing exists, so the .app is unpacked
# straight from the developer's release DMG. nix-darwin links it into
# /Applications/Nix Apps on switch. The app's own Sparkle auto-update can't
# write to the read-only store; bump `version`/`hash` here to update.
pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "transcripted";
  version = "1.1.59";

  src = pkgs.fetchurl {
    url = "https://github.com/r3dbars/transcripted/releases/download/v${finalAttrs.version}/Transcripted-${finalAttrs.version}.dmg";
    hash = "sha256-4kXxSLKqGUN2JLGY0J+csYYh+9Y5CTmfv7pF85XQoJw=";
  };

  nativeBuildInputs = [ pkgs.undmg ];
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    cp -R "Transcripted.app" "$out/Applications/"
    runHook postInstall
  '';

  meta = {
    description = "Transcripted macOS app (github.com/r3dbars/transcripted)";
    platforms = pkgs.lib.platforms.darwin;
  };
})
