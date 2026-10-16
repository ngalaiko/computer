{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

# No Homebrew cask or Mac App Store listing exists, so the .app is unpacked
# straight from the developer's release DMG. nix-darwin links it into
# /Applications/Nix Apps on switch. The app's own Sparkle auto-update can't
# write to the read-only store; bump `version`/`hash` here to update.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "transcripted";
  version = "1.1.70";

  src = fetchurl {
    url = "https://github.com/r3dbars/transcripted/releases/download/v${finalAttrs.version}/Transcripted-${finalAttrs.version}.dmg";
    hash = "sha256-crpDC2g/6pvspSgGZJCW5C/xBkbw3FPyO7Ffemchd5s=";
  };

  nativeBuildInputs = [ undmg ];
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    cp -R "Transcripted.app" "$out/Applications/"
    runHook postInstall
  '';

  meta = {
    description = "Transcripted macOS app (github.com/r3dbars/transcripted)";
    platforms = lib.platforms.darwin;
  };
})
