{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.services.tailscale;

  # Each node is its own tailscaled instance (== its own tailnet device and
  # MagicDNS name), so per-node runtime paths keep them from colliding.
  runDirOf = name: "/run/tailscale-${name}";
  socketOf = name: "${runDirOf name}/tailscaled.sock";
  stateDirOf = name: "/var/lib/tailscale-${name}";
  tsCli = name: "${pkgs.tailscale}/bin/tailscale --socket=${socketOf name}";

  # funnel (public) only listens on these ports; serve (tailnet-private) is
  # unrestricted.
  funnelPorts = [
    443
    8443
    10000
  ];
  # A serve entry renders to one of three CLI shapes:
  #   service != null -> `serve --service=svc:… ` (stable tailnet Service on its
  #                      own VIP; tailnet-only, so funnel is disallowed).
  #   funnel          -> `funnel …`               (public, on the node's own name).
  #   otherwise       -> `serve …`                (tailnet-private, node's name).
  serveLine =
    name: e:
    let
      pathArg = lib.optionalString (e.path != null) " --set-path=${e.path}";
    in
    assert lib.assertMsg (!(e.funnel && e.service != null))
      "services.tailscale.nodes.${name}.serve: funnel and service are mutually exclusive (Tailscale Services are tailnet-only) for ${e.target}.";
    assert lib.assertMsg (!e.funnel || lib.elem e.port funnelPorts)
      "services.tailscale.nodes.${name}.serve: funnel port must be 443, 8443, or 10000 (got ${toString e.port} for ${e.target}).";
    if e.service != null then
      "${tsCli name} serve --service=${e.service} --bg --https=${toString e.port}${pathArg} ${e.target}"
    else
      "${tsCli name} ${
        if e.funnel then "funnel" else "serve"
      } --bg --https=${toString e.port}${pathArg} ${e.target}";

  serveType = types.listOf (
    types.submodule {
      options = {
        target = mkOption {
          type = types.str;
          example = "localhost:9999";
          description = "Local upstream tailscale proxies to (host:port, bare port, or URL).";
        };
        port = mkOption {
          type = types.port;
          default = 443;
          description = "Tailnet HTTPS port to bind. funnel accepts only 443, 8443, or 10000.";
        };
        path = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "/cptr";
          description = "Optional path prefix to mount the target under (--set-path).";
        };
        funnel = mkOption {
          type = types.bool;
          default = false;
          description = "Expose to the public internet via Funnel (needs the funnel nodeAttr in the tailnet ACL) instead of tailnet-private serve. Mutually exclusive with service.";
        };
        service = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "svc:cptr";
          description = ''
            Advertise this target as a Tailscale Service (svc:… name) instead of
            on the node's own name. The Service lives in the tailnet policy and
            gets its own stable, node-independent MagicDNS name + VIP, so it
            survives node re-registration. The node must be tagged and the svc:
            name auto-approved for those tags in the policy (see README).
            Tailnet-only — mutually exclusive with funnel.
          '';
        };
      };
    }
  );

  # the s6 services backing one node: tailscaled + tailscale-up, plus a
  # tailscale-serve when it has serve/funnel targets.
  nodeServices =
    name: node:
    let
      sock = socketOf name;
      cli = tsCli name;
      backupDep = lib.optional config.services.backup.enable "backup-restore";
      # up args, joined here so an absent --ssh can't leave a dangling `\`.
      upArgs = lib.concatStringsSep " " (
        lib.optional node.ssh "--ssh"
        ++ [
          "--hostname=${node.hostname}"
          "--advertise-tags=${lib.concatStringsSep "," node.tags}"
          "--accept-dns=false"
          "--auth-key=file:${cfg.authKeyFile}"
        ]
      );
    in
    {
      # --statedir is REQUIRED for an ssh node: tailscaled stores the Tailscale
      # SSH host keys there and silently disables SSH without it ("no var root
      # for ssh keys"); --state=mem has no such root. It also holds the node key
      # so a restart reclaims the same device (stable MagicDNS name). It lives on
      # the persistent disk and is deliberately NOT backed up — it regenerates: a
      # fresh disk registers a new node (ephemeral key => the retired one
      # auto-removes when offline; see README).
      #
      # tun: ssh needs the kernel tun (the userspace netstack doesn't answer ssh,
      # 1.90.9). Non-ssh nodes run --tun=userspace-networking — no /dev/net/tun,
      # and serve/funnel still work (tailscaled terminates TLS and proxies to
      # localhost). --port=0 auto-selects a WireGuard port so co-located nodes
      # don't fight over 41641. Only one kernel-tun node is supported as written
      # (they'd share the tailscale0 device); userspace nodes are unbounded.
      "tailscaled-${name}" = {
        dependencies = [ "base" ] ++ backupDep;
        run = ''
          mkdir -p ${runDirOf name} ${stateDirOf name}
        ''
        + lib.optionalString node.ssh ''
          if [ ! -e /dev/net/tun ]; then
            mkdir -p /dev/net
            mknod /dev/net/tun c 10 200 || true
          fi
        ''
        + lib.optionalString node.localApiReadable ''
          chmod 0755 ${runDirOf name}
          # widen the LocalAPI socket for read-only local callers once tailscaled
          # creates it (see node.localApiReadable). Backgrounded so it doesn't
          # block the exec; re-runs on every tailscaled (re)start.
          (
            until [ -S ${sock} ]; do sleep 1; done
            chmod 0666 ${sock}
          ) &
        ''
        + ''
          exec ${pkgs.tailscale}/bin/tailscaled \
            --statedir=${stateDirOf name} \
            --socket=${sock} \
            --port=0 \
            --tun=${if node.ssh then "tailscale0" else "userspace-networking"}
        '';
      };

      # a longrun, not a oneshot: the non-PID1 boot path runs every oneshot
      # before any longrun, so a oneshot could never wait for tailscaled.
      # failures exit and s6's restart is the retry loop.
      "tailscale-up-${name}" = {
        dependencies = [
          "base"
          "tailscaled-${name}"
        ]
        ++ backupDep;
        run = ''
          if [ ! -f ${cfg.authKeyFile} ]; then
            echo "tailscale(${name}): ${cfg.authKeyFile} missing — sleeping." >&2
            exec /command/s6-pause
          fi
          i=0
          until [ -S ${sock} ]; do
            i=$((i + 1))
            [ $i -ge 30 ] && exit 1
            sleep 1
          done
          ${cli} up ${upArgs} || {
            sleep 2
            exit 1
          }
          exec /command/s6-pause
        '';
      };
    }
    // lib.optionalAttrs (node.serve != [ ]) {
      # Reconstructs the full serve/funnel/service config from node.serve on
      # every boot. `serve reset` first, so the declared list is authoritative;
      # node-local serve state lives in the un-backed-up statedir and re-applying
      # is idempotent. Service (svc:…) advertisements are re-asserted here too and
      # auto-approved via the tailnet policy, so a re-registered node re-hosts the
      # same stable Service name with no manual step. A longrun (like
      # tailscale-up) that pauses once applied; any failure exits and s6 retries.
      # The svscan boot path doesn't order longruns, so we can't assume
      # tailscale-up finished — poll for BackendState=Running first.
      "tailscale-serve-${name}" = {
        dependencies = [
          "base"
          "tailscaled-${name}"
          "tailscale-up-${name}"
        ];
        run = ''
          i=0
          until [ -S ${sock} ]; do
            i=$((i + 1))
            [ $i -ge 30 ] && exit 1
            sleep 1
          done
          i=0
          until ${cli} status --json 2>/dev/null | grep -q '"BackendState": *"Running"'; do
            i=$((i + 1))
            [ $i -ge 120 ] && exit 1
            sleep 1
          done
          ${cli} serve reset || true
          ${lib.concatMapStringsSep "\n" (e: "${serveLine name e} || { sleep 2; exit 1; }") node.serve}
          exec /command/s6-pause
        '';
      };
    };
in
{
  options.services.tailscale = {
    enable = lib.mkEnableOption "tailscale nodes on this host (persistent tailnet devices; optional tailscale ssh and serve/funnel)";

    authKeyFile = mkOption {
      type = types.str;
      default = "/var/lib/tailscale/authkey";
      description = "File holding an OAuth client secret (tskey-client-...?preauthorized=true) or a reusable tagged auth key, shared by every node; place it by hand once and let services.backup preserve it. No key -> tailscale is skipped.";
    };

    tags = mkOption {
      type = types.listOf types.str;
      default = [ "tag:computer" ];
      description = "Default advertised tags for nodes that don't override; mandatory when joining via an OAuth client secret.";
    };

    nodes = mkOption {
      default = { };
      description = ''
        Tailnet nodes to run on this host. Each is a separate tailscaled instance
        — its own tailnet device and MagicDNS name. A single node can still own
        :443 several times over: once on its own IP (serve or funnel) plus once
        per Tailscale Service it hosts (each Service has its own VIP). All nodes
        register with the shared authKeyFile.
      '';
      example = lib.literalExpression ''
        {
          computer.ssh = true;                                   # ssh host (kernel tun)
          cptr.serve = [ { target = "localhost:9999"; } ];       # private, ts.net root
        }
      '';
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              hostname = mkOption {
                type = types.str;
                default = name;
                description = "Tailnet hostname (MagicDNS name) for this node.";
              };
              ssh = mkOption {
                type = types.bool;
                default = false;
                description = "Enable Tailscale SSH on this node. Requires (and switches the node to) the kernel tun.";
              };
              localApiReadable = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Widen this node's tailscaled LocalAPI socket to 0666 once it is
                  created, so any local user (e.g. an unprivileged service
                  account) can run read-only commands like `tailscale status` /
                  `tailscale funnel status`. tailscaled authorizes *mutating*
                  calls by the caller's unix peer credentials, not by socket
                  mode, so writes stay root-only. Off by default (root-only).
                '';
              };
              tags = mkOption {
                type = types.listOf types.str;
                default = cfg.tags;
                description = "Advertised device tags for this node; defaults to services.tailscale.tags.";
              };
              serve = mkOption {
                default = [ ];
                type = serveType;
                description = ''
                  Declarative `tailscale serve`/`funnel` targets for this node,
                  reconstructed on every boot. Each entry proxies the tailnet
                  HTTPS <port> to a local <target>. Rides the tailnet interface,
                  so it needs no image.exposedPorts / exe.dev share. Requires
                  HTTPS Certificates enabled in the tailnet; funnel additionally
                  requires the `funnel` nodeAttr for the tags (see README).
                '';
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkIf cfg.enable {
    image.packages = [ pkgs.tailscale ];

    # Back up only the hand-placed authKeyFile (the one non-regenerating bit), so
    # recreation is zero-touch. Every node's tailscaled state lives in its own
    # un-backed-up statedir (see tailscaled-<name> above).
    services.backup.paths = [ cfg.authKeyFile ];

    s6.services = lib.mkMerge (lib.mapAttrsToList nodeServices cfg.nodes);
  };
}
