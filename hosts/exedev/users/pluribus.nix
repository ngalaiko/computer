{
  pkgs,
  inputs,
  config,
  ...
}:
let
  package = inputs.pluribus.packages.${pkgs.stdenv.hostPlatform.system}.default;
  executor = inputs.pluribus.packages.${pkgs.stdenv.hostPlatform.system}.plugin-shell;
  emailStreams =
    (builtins.fromJSON (builtins.readFile ../pluribus/config.json))
    .plugin_instances.email.access.stream;
  emailEndpoints = pkgs.writeText "pluribus-email-endpoints.json" (
    builtins.toJSON (builtins.mapAttrs (_: endpoint: endpoint.tls) emailStreams)
  );
  obsidian-headless = import ../../../packages/obsidian-headless { inherit pkgs; };
  obsidian-sync = pkgs.writeShellScriptBin "obsidian-sync" ''
    set -eu
    vault="''${OBSIDIAN_VAULT_DIR:-/home/pluribus/Vault}"
    exec ${obsidian-headless}/bin/ob sync --path "$vault" "$@"
  '';
  home = "/home/pluribus";
  data = "/home/nikita/.local/share/pluribus";
  configDir = "/home/nikita/.config/pluribus";
  uid = 2002;
  gid = config.users.groups.pluribus.gid;
  runtimeUid = config.users.users.nikita.uid;
  core = pkgs.writeShellScript "pluribus-core" ''
    set -eu
    umask 0077
    cd /home/nikita
    exec ${package}/bin/pluribus run
  '';

in
{
  services.ingress.routes = ''
    handle_path /nikita/pluribus/github/* {
      reverse_proxy 127.0.0.1:8090
    }
  '';

  # Isolated public namespace; tenant-owned config and reload socket.
  services.ingress.tenants.pluribus = {
    upstreamPort = 8084;
  };

  users.users.pluribus = {
    inherit uid home;
    group = "pluribus";
    createHome = true;
    locked = true;
    shell = "${pkgs.bashInteractive}/bin/bash";
    description = "Pluribus shell executor";
    packages = [
      pkgs.gh
      pkgs.chromium
      obsidian-headless
      obsidian-sync
    ];
  };
  users.groups.pluribus = {
    gid = uid;
    members = [ "nikita" ];
  };
  users.users.nikita.packages = [ package ];
  services.backup.paths = [ home ];

  s6.services.pluribus-prepare = {
    type = "oneshot";
    dependencies = [
      "base"
      "backup-restore"
    ];
    reactivate = true;
    run = ''
      set -eu
      install -d -m 0750 -o ${toString uid} -g ${toString gid} ${home}
      install -d -m 0700 -o ${toString runtimeUid} ${data} ${configDir}
      ln -sfn ${../pluribus/config.json} ${configDir}/config.json
      install -d -m 0750 -o ${toString uid} -g ${toString gid} ${home}/.config/email
      ln -sfn ${emailEndpoints} ${home}/.config/email/endpoints.json
    '';
  };

  # Auth, sync configuration and vault stay in the backed-up executor home.
  s6.services.pluribus-obsidian-sync = {
    dependencies = [ "pluribus-prepare" ];
    run = ''
      exec /command/s6-setuidgid pluribus \
        env -i HOME=${home} USER=pluribus SHELL=/bin/sh \
        PATH=/etc/profiles/per-user/pluribus/bin:/bin \
        NODE_EXTRA_CA_CERTS=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
        ${pkgs.writeShellScript "pluribus-obsidian-sync" ''
          set -eu
          umask 0077
          if [ ! -d "${home}/Vault/.obsidian" ]; then
            echo "pluribus-obsidian-sync: run ob login and ob sync-setup first; retrying in 30s" >&2
            sleep 30
            exit 1
          fi
          exec ${obsidian-headless}/bin/ob sync --path ${home}/Vault --continuous
        ''}
    '';
  };

  s6.services.pluribus = {
    dependencies = [ "pluribus-prepare" ];
    run = ''
      exec /command/s6-setuidgid nikita \
        env -i HOME=/home/nikita USER=nikita \
        PATH=/etc/profiles/per-user/nikita/bin:/bin \
        SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
        ${core}
    '';
  };

  s6.services.pluribus-http = {
    dependencies = [ "pluribus-prepare" ];
    run = ''
      exec /command/s6-setuidgid nikita \
        ${package}/bin/pluribus-http-listener \
          --listen 127.0.0.1:8090 \
          --socket ${data}/http.sock \
          --runtime-uid ${toString runtimeUid} \
          --max-body-bytes ${toString (25 * 1024 * 1024)} \
          --response-timeout-seconds 60 \
          --route "github:GET,POST:/*:github/receive"
    '';
  };

  s6.services.pluribus-shell = {
    dependencies = [ "pluribus-prepare" ];
    run = ''
      exec /command/s6-setuidgid pluribus \
        env -i HOME=${home} USER=pluribus PATH=/bin:/usr/bin \
        /bin/sh -ec '
          umask 0077
          cd ${home}
          mkdir -p ${home}/.runtime
          chmod 0750 ${home}/.runtime
          rm -f ${home}/.runtime/executor.sock
          exec ${executor}/bin/pluribus-shell-executor \
            --socket ${home}/.runtime/executor.sock \
            --workspace ${home} \
            --path ${home}/.local/bin:/etc/profiles/per-user/pluribus/bin:/usr/local/bin:/usr/bin:/bin \
            --runtime-uid ${toString config.users.users.nikita.uid}
        '
    '';
  };
}
