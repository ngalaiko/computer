{ pkgs, inputs, ... }:
let
  # cptr isn't in nixpkgs; we package it from its PyPI wheel, built against
  # unstable's python3Packages (its dep floors exceed nixpkgs-25.11). It ships
  # under the unfree "Open Use License" (ELv2 + attribution), so allow just it.
  unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfreePredicate = p: pkgs.lib.getName p == "cptr";
  };
in
{
  services.cptr = {
    enable = true;
    package = import ../../../packages/cptr { pkgs = unstable; };
  };

  # A persistent headless Chromium running as the cptr account, CDP on
  # 127.0.0.1:9222, so cptr can drive a real browser over localhost. Loopback
  # only — CDP is unauthenticated remote control, never exposed off-box.
  services.chrome.enable = true;

  # cptr's terminal + git features shell out to these; on the cptr user's PATH.
  # The account is unprivileged (no sudo, not nix-trusted), which caps what a
  # signed-in user can do on the box.
  users.users.cptr.packages = with pkgs; [
    git
    gh
    jq
    ripgrep
    curl
    coreutils
    uv
    # pydub (cptr audio) shells out to ffmpeg/ffprobe; headless = no X/GUI closure.
    ffmpeg-headless
    # read-only tailscale CLI: `tailscale --socket=… status/funnel status` to
    # report the machine's current public hostname (see the public-hostname
    # skill). The daemon socket is opened read-only to local users via
    # services.tailscale.nodes.computer.localApiReadable; writes stay root-only.
    tailscale
  ];

  # cptr's self-serve public exposure. A per-cptr caddy on the shared 8080
  # ingress with /cptr/* routed to it: from inside cptr, edit ~/.caddy/Caddyfile
  # and `caddy reload` to reverse_proxy whatever you're running and publish it to
  # the internet — the same facility nikita has. Separate from cptr's own UI
  # (which stays on 9999); the seed just 404s until you point it somewhere.
  services.ingress.tenants.cptr.upstreamPort = 8083;

  services.backup = {
    enable = true;
    # cptr's admin account + db + workspaces, and the tenant caddy's Caddyfile
    # (~/.caddy), all live here.
    paths = [ "/var/lib/cptr" ];
  };
}
