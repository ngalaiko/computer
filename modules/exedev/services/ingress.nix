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

  # binds the public port; routes each /<name>/* to a tenant's loopback caddy
  # with the prefix stripped.
  rootCaddyfile = pkgs.writeText "ingress-root.Caddyfile" (
    lib.concatStringsSep "\n" (
      [
        "{"
        "\tadmin off"
        "\tauto_https off"
        "}"
        ""
        ":${toString cfg.publicPort} {"
      ]
      ++ map (
        t: "\thandle_path /${t.name}/* {\n\t\treverse_proxy 127.0.0.1:${toString t.upstreamPort}\n\t}"
      ) tenants
      ++ [
        "\thandle {"
        "\t\trespond \"not found\" 404"
        "\t}"
        "}"
        ""
      ]
    )
  );

  # tab-indent each non-blank route line so the rendered seed is caddy-fmt clean.
  indent =
    text:
    lib.concatStringsSep "\n" (map (l: if l == "" then l else "\t${l}") (lib.splitString "\n" text));

  # runtime dir (0700, owned by the tenant) holding the caddy admin socket.
  rundirOf = t: "/run/ingress-${t.name}";

  # the tenant's Caddyfile, rendered when absent; user-owned afterward. The
  # admin socket in the 0700 rundir lets the user `caddy reload` in place, and
  # no other non-root user can reach it.
  seedFile =
    t:
    pkgs.writeText "ingress-${t.name}-seed.Caddyfile" (
      lib.concatStringsSep "\n" [
        "{"
        "\tadmin unix/${rundirOf t}/admin.sock"
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
                description = "Seed route body spliced into the tenant's site block on first boot; user-owned after.";
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkIf cfg.enable {
    image.exposedPorts.tcp = [ cfg.publicPort ];

    # tenants manage their routes with `caddy reload`, so put caddy on their PATH.
    users.users = lib.listToAttrs (
      map (t: lib.nameValuePair t.user { packages = [ pkgs.caddy ]; }) tenants
    );

    s6.services = lib.mkMerge (
      [
        {
          ingress-root = {
            dependencies = [ "base" ];
            run = ''
              mkdir -p /run/ingress-root
              exec env HOME=/run/ingress-root XDG_DATA_HOME=/run/ingress-root XDG_CONFIG_HOME=/run/ingress-root \
                ${pkgs.caddy}/bin/caddy run --config ${rootCaddyfile} --adapter caddyfile
            '';
          };
        }
      ]
      ++ map (
        t:
        let
          u = config.users.users.${t.user};
          gid = toString config.users.groups.${u.group}.gid;
          caddyDir = "${u.home}/.caddy";
          caddyfile = "${caddyDir}/Caddyfile";
          rundir = rundirOf t;
        in
        {
          # write the Caddyfile only when absent.
          "ingress-${t.name}-setup" = {
            type = "oneshot";
            dependencies = [
              "base"
            ]
            ++ lib.optional config.services.backup.enable "backup-restore";
            run = ''
              mkdir -p ${caddyDir}
              [ -e ${caddyfile} ] || cp ${seedFile t} ${caddyfile}
              chown -R ${toString u.uid}:${gid} ${caddyDir}
            '';
          };
          "ingress-${t.name}" = {
            dependencies = [
              "base"
              "ingress-${t.name}-setup"
            ];
            run = ''
              mkdir -p ${rundir}
              chown ${toString u.uid}:${gid} ${rundir}
              chmod 700 ${rundir}
              exec /command/s6-setuidgid ${t.user} \
                env HOME=${u.home} XDG_DATA_HOME=${rundir} XDG_CONFIG_HOME=${rundir} \
                ${pkgs.caddy}/bin/caddy run --config ${caddyfile} --adapter caddyfile
            '';
          };
        }
      ) tenants
    );
  };
}
