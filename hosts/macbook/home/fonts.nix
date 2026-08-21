{ ... }:
{
  # Licensed fonts (e.g. Berkeley Mono) in ./fonts are symlinked into
  # ~/Library/Fonts so macOS/Ghostty can find them.
  home.file."Library/Fonts" = {
    source = ./fonts;
    recursive = true;
  };
}
