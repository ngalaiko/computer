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

    # --state=mem:: a fresh ephemeral node every boot, auto-removed after
    # going offline — recreated VMs never fight over a node key.
    # kernel tun (userspace netstack never answered ssh in 1.90.9); the
    # device node isn't pre-created in the image, and netfilter needs
    # iptables the image doesn't ship.
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
          --netfilter-mode=off \
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
          --advertise-tags=${lib.concatStringsSep "," cfg.tags} \
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
