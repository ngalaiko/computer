{ config, lib, ... }:
let
  fonts = builtins.path {
    name = "fonts";
    path = ./.;
    filter = path: _: lib.hasSuffix ".otf" path;
  };
in
{
  # Licensed fonts (e.g. Berkeley Mono) next to this file are copied into
  # ~/Library/Fonts. macOS does not register symlinked fonts, so
  # home.file would hide them from CoreText apps.
  home.activation.copyFonts = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    for f in ${fonts}/*; do
      dst=${config.home.homeDirectory}/Library/Fonts/$(basename "$f")
      run rm -f "$dst"
      run install -m644 "$f" "$dst"
    done
  '';
}
