{ pkgs, inputs, ... }:
let
  # open-webui from unstable for the newer release (25.11 stops at 0.8.x). Its
  # license (BSD-3 plus a branding clause since 0.6.6) is marked unfree, so
  # allow just it.
  unfree = import ../../../packages/unstable.nix {
    inherit inputs pkgs;
    allowUnfree = [ "open-webui" ];
  };
in
{
  services.open-webui = {
    enable = true;
    package = unfree.open-webui;
  };

  # pydub (open-webui audio: STT/TTS transcoding) shells out to ffmpeg/ffprobe
  # and warns at startup without it; headless = no X/GUI closure, and it's
  # already in the image via the cptr account so it adds nothing.
  users.users.open-webui.packages = [ pkgs.ffmpeg-headless ];

  services.backup = {
    enable = true;
    # accounts db + uploads + vector db + the JWT secret key all live here.
    paths = [ "/var/lib/open-webui" ];
  };
}
