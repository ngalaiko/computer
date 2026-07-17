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
      description = "File holding an OAuth client secret (tskey-client-...?preauthorized=true) or a tagged auth key; place it by hand once and let services.backup preserve it. No key -> tailscale is skipped.";
    };
    tags = mkOption {
      type = types.listOf types.str;
      default = [ "tag:exedev" ];
      description = "Advertised device tags; mandatory when joining via an OAuth client secret.";
    };
  };

  config = lib.mkIf cfg.enable {
    image.packages = [ pkgs.tailscale ];

    services.backup.paths = [ (builtins.dirOf cfg.authKeyFile) ];

    # --state=mem:: ephemeral node per boot, so overlapping recreated VMs
    # never share a node key. --statedir must still be set: without a var
    # root tailscaled has no ssh host keys and silently disables ssh.
    # kernel tun — the userspace netstack doesn't answer ssh (1.90.9).
    s6.services.tailscaled = {
      dependencies = [ "base" ];
      run = ''
        mkdir -p /run/tailscale
        if [ ! -e /dev/net/tun ]; then
          mkdir -p /dev/net
          mknod /dev/net/tun c 10 200 || true
        fi
        exec ${pkgs.tailscale}/bin/tailscaled \
          --state=mem: \
          --statedir=/var/lib/tailscale \
          --socket=${socket}
      '';
    };

    # a longrun, not a oneshot: the non-PID1 boot path runs every oneshot
    # before any longrun, so a oneshot could never wait for tailscaled.
    # failures exit and s6's restart is the retry loop.
    s6.services.tailscale-up = {
      dependencies = [
        "base"
        "tailscaled"
      ]
      ++ lib.optional config.services.backup.enable "backup-restore";
      run = ''
        if [ ! -f ${cfg.authKeyFile} ]; then
          echo "tailscale: ${cfg.authKeyFile} missing — sleeping." >&2
          exec /command/s6-pause
        fi
        i=0
        until [ -S ${socket} ]; do
          i=$((i + 1))
          [ $i -ge 30 ] && exit 1
          sleep 1
        done
        ${tailscale} up \
          --ssh \
          --hostname=${cfg.hostname} \
          --advertise-tags=${lib.concatStringsSep "," cfg.tags} \
          --accept-dns=false \
          --auth-key=file:${cfg.authKeyFile} || {
          sleep 2
          exit 1
        }
        exec /command/s6-pause
      '';
      # immediate node removal instead of the ephemeral timeout; only on
      # signal-death (shutdown), not on retry exits
      finish = ''
        [ "$1" = 256 ] && ${tailscale} logout || true
      '';
    };
  };
}
