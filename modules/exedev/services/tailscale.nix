{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.services.tailscale;
  socket = "/run/tailscale/tailscaled.sock";
  tailscale = "${pkgs.tailscale}/bin/tailscale --socket=${socket}";
in
{
  options.services.tailscale = {
    enable = lib.mkEnableOption "tailscale as an ephemeral tailnet node with tailscale ssh";
    hostname = mkOption {
      type = types.str;
      default = "computer";
      description = "Tailnet hostname (MagicDNS name).";
    };
    authKeyFile = mkOption {
      type = types.str;
      default = "/var/lib/tailscale/authkey";
      description = "File holding a reusable+ephemeral+preauthorized tagged auth key; place it by hand once and let services.backup preserve it. No key -> tailscale is skipped.";
    };
  };

  config = lib.mkIf cfg.enable {
    image.packages = [ pkgs.tailscale ];

    services.backup.paths = [ (builtins.dirOf cfg.authKeyFile) ];

    # --state=mem:: a fresh ephemeral node every boot, auto-removed after
    # going offline — recreated VMs never fight over a node key.
    # userspace networking: no /dev/net/tun dependency; inbound tailscale
    # ssh terminates inside tailscaled, which is all this node serves.
    s6.services.tailscaled = {
      dependencies = [ "base" ];
      run = ''
        mkdir -p /run/tailscale
        exec ${pkgs.tailscale}/bin/tailscaled \
          --state=mem: \
          --tun=userspace-networking \
          --socket=${socket}
      '';
    };

    s6.services.tailscale-up = {
      type = "oneshot";
      dependencies = [
        "base"
        "tailscaled"
      ]
      ++ lib.optional config.services.backup.enable "backup-restore";
      run = ''
        if [ ! -f ${cfg.authKeyFile} ]; then
          echo "tailscale: ${cfg.authKeyFile} missing — skipping." >&2
          exit 0
        fi
        i=0
        until ${tailscale} up \
          --ssh \
          --hostname=${cfg.hostname} \
          --accept-dns=false \
          --auth-key=file:${cfg.authKeyFile}; do
          i=$((i + 1))
          [ $i -ge 10 ] && exit 1
          sleep 2
        done
      '';
      # immediate node removal instead of the ephemeral timeout
      down = ''
        ${tailscale} logout || true
      '';
    };
  };
}
