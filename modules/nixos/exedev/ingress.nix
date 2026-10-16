{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.services.ingress;

  tenants = lib.mapAttrsToList (name: t: t // { inherit name; }) cfg.tenants;

  # tab-indent each non-blank route line so the rendered seed is caddy-fmt clean.
  indent =
    text:
    lib.concatStringsSep "\n" (map (l: if l == "" then l else "\t${l}") (lib.splitString "\n" text));

  # the tenant's Caddyfile, copied when absent; user-owned afterward. The admin
  # socket in the 0700 runtime dir lets the user `caddy reload` in place, and no
  # other non-root user can reach it.
  seedFile =
    t:
    pkgs.writeText "ingress-${t.name}-seed.Caddyfile" (
      lib.concatStringsSep "\n" [
        "{"
        "\tadmin unix//run/ingress-${t.name}/admin.sock"
        "\tauto_https off"
        "}"
        ""
        ":${toString t.upstreamPort} {"
        (indent (lib.removeSuffix "\n" t.routes))
        "}"
        ""
      ]
    );
in
{
  options.services.ingress = {
    enable = lib.mkEnableOption "the public path-routed ingress (root caddy + per-user self-serve tenant caddies)";

    routes = mkOption {
      type = types.lines;
      default = "";
      description = "Declarative routes in the public site, alongside tenant routes.";
    };

    publicPort = mkOption {
      type = types.port;
      default = 8080;
      description = ''
        Port the root caddy binds and the image exposes. Meant to be exe.dev's
        primary (root-URL) port; the deploy pins it with `share port` and
        publishes it with `share set-public`.
      '';
    };

    tenants = mkOption {
      default = { };
      description = ''
        Per-user subtrees under /<name>/* on the public port. Each runs a caddy
        as its user, reading a Caddyfile the user owns and can reload, so a user
        can expose new services at runtime without a rebuild or root.
      '';
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              user = mkOption {
                type = types.str;
                default = name;
                description = "User the tenant caddy runs as (must be a declared user).";
              };
              upstreamPort = mkOption {
                type = types.port;
                description = "Loopback port the tenant caddy binds; root forwards /<name>/* here (prefix stripped).";
              };
              routes = mkOption {
                type = types.lines;
                default = "respond \"${name}: no routes configured yet\" 404";
                description = "Seed route body spliced into the tenant's site block when its Caddyfile is absent; user-owned after.";
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkIf cfg.enable {
    exedev.image.exposedPorts.tcp = [ cfg.publicPort ];

    # binds the public port; routes each /<name>/* to a tenant's loopback caddy
    # with the prefix stripped.
    services.caddy = {
      enable = true;
      enableReload = false;
      globalConfig = ''
        admin off
        auto_https off
      '';
      extraConfig = ''
        :${toString cfg.publicPort} {
          ${cfg.routes}
          ${lib.concatMapStrings (t: ''
            handle_path /${t.name}/* {
              reverse_proxy 127.0.0.1:${toString t.upstreamPort}
            }
          '') tenants}
          handle {
            respond "not found" 404
          }
        }
      '';
    };

    # tenants manage their routes with `caddy reload`, so put caddy on their PATH.
    users.users = lib.listToAttrs (
      map (t: lib.nameValuePair t.user { packages = [ pkgs.caddy ]; }) tenants
    );

    systemd.services = lib.listToAttrs (
      map (
        t:
        let
          home = config.users.users.${t.user}.home;
          caddyfile = "${home}/.caddy/Caddyfile";
        in
        lib.nameValuePair "ingress-${t.name}" {
          wantedBy = [ "multi-user.target" ];
          # a restored Caddyfile wins over the seed.
          wants = [ "backup-restore.service" ];
          after = [ "backup-restore.service" ];
          environment = {
            HOME = home;
            XDG_DATA_HOME = "/run/ingress-${t.name}";
            XDG_CONFIG_HOME = "/run/ingress-${t.name}";
          };
          preStart = ''
            mkdir -p ${home}/.caddy
            [ -e ${caddyfile} ] || install -m 0644 ${seedFile t} ${caddyfile}
          '';
          serviceConfig = {
            User = t.user;
            RuntimeDirectory = "ingress-${t.name}";
            RuntimeDirectoryMode = "0700";
            ExecStart = "${lib.getExe pkgs.caddy} run --config ${caddyfile} --adapter caddyfile";
            ExecReload = "${lib.getExe pkgs.caddy} reload --config ${caddyfile} --adapter caddyfile --address unix//run/ingress-${t.name}/admin.sock";
            Restart = "always";
            RestartSec = 5;
          };
          startLimitIntervalSec = 0;
        }
      ) tenants
    );
  };
}
