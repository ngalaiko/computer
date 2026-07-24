{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.services.chrome;
  user = config.users.users.${cfg.user};
  gid = toString config.users.groups.${user.group}.gid;

  # Chromium aborts on startup without a usable fontconfig and at least one font
  # (Skia's FontConfigInterface FATALs with "Not implemented"). The base image
  # ships neither, so hand the process a minimal, self-contained fonts.conf
  # pointing at DejaVu via FONTCONFIG_FILE — no global /etc/fonts needed.
  fontsConf = pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; };
in
{
  options.services.chrome = {
    enable = lib.mkEnableOption "headless Chromium exposing a Chrome DevTools Protocol (CDP) endpoint, supervised by s6";
    package = mkOption {
      type = types.package;
      default = pkgs.chromium;
      defaultText = lib.literalExpression "pkgs.chromium";
      description = "Chromium package (must expose bin/chromium).";
    };
    user = mkOption {
      type = types.str;
      default = "cptr";
      description = "Non-root account the browser runs as; the CDP endpoint drives this account's browser. Defaults to the cptr account (declared by services.cptr), so cptr can automate a browser over localhost.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/chrome";
      description = "Chromium's HOME and --user-data-dir (cache, crash dumps). Churny and disposable — deliberately outside the cptr backup set.";
    };
    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address the CDP endpoint binds. Keep it on loopback: CDP is unauthenticated, full remote control of the browser, so it must never leave the box.";
    };
    port = mkOption {
      type = types.port;
      default = 9222;
      description = "Port the CDP endpoint listens on (loopback only; intentionally not an image-exposed port).";
    };
    extraFlags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra flags appended to the chromium invocation.";
    };
  };

  config = lib.mkIf cfg.enable {
    s6.services.chrome-setup = {
      type = "oneshot";
      dependencies = [ "base" ];
      run = ''
        mkdir -p ${cfg.stateDir}
        chown -R ${toString user.uid}:${gid} ${cfg.stateDir}
      '';
    };

    # Runs unprivileged as ${cfg.user}, headless (no X, no GPU). s6 supervises and
    # restarts it. --no-sandbox: the container ships no setuid sandbox helper and
    # unprivileged user namespaces are off, so Chromium's own sandbox can't start;
    # the container plus this unprivileged account are the boundary here.
    # --disable-dev-shm-usage keeps Chromium off the container's tiny /dev/shm
    # (otherwise it crashes under memory pressure). The CDP endpoint binds loopback
    # only (see services.chrome.address) — it is unauthenticated remote control, so
    # it is deliberately NOT added to image.exposedPorts.
    s6.services.chrome = {
      dependencies = [
        "base"
        "chrome-setup"
      ];
      run = ''
        cd ${cfg.stateDir}
        exec /command/s6-setuidgid ${cfg.user} \
          env \
            HOME=${cfg.stateDir} \
            USER=${cfg.user} \
            FONTCONFIG_FILE=${fontsConf} \
          ${cfg.package}/bin/chromium \
            --headless=new \
            --no-sandbox \
            --disable-gpu \
            --disable-dev-shm-usage \
            --no-first-run \
            --user-data-dir=${cfg.stateDir}/profile \
            --remote-debugging-address=${cfg.address} \
            --remote-debugging-port=${toString cfg.port} \
            --remote-allow-origins='*' \
            ${lib.escapeShellArgs cfg.extraFlags}
      '';
    };

    image.packages = [ cfg.package ];
  };
}
