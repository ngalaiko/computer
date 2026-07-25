# Shared nixpkgs-unstable instantiation for packages whose dep floors exceed
# nixpkgs-25.11, so every unstable consumer gets the same image-wide fixups.
{
  inputs,
  pkgs,
  # unfree package names (lib.getName) to allow, e.g. [ "cptr" ].
  allowUnfree ? [ ],
}:
import inputs.nixpkgs-unstable {
  inherit (pkgs.stdenv.hostPlatform) system;
  config.allowUnfreePredicate = p: builtins.elem (pkgs.lib.getName p) allowUnfree;
  overlays = [
    (final: prev: {
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (pyfinal: pyprev: {
          # nixpkgs patches pydub to hardcode ffmpeg paths, and the default
          # full ffmpeg links SDL3 -> GTK/gstreamer/pipewire — ~460 MB of
          # desktop stack this headless image never uses. ffmpeg-headless
          # keeps ffmpeg/ffprobe (and mp3); only pydub.playback loses ffplay.
          pydub = pyprev.pydub.override { ffmpeg = final.ffmpeg-headless; };
        })
      ];
    })
  ];
}
