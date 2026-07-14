# Shelley (exe.dev's coding agent) under s6: runs as the login user via
# s6-setuidgid, with its database under that user's XDG config dir. The user
# is referenced by name only; declare the account in the system config.
{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.services.shelley;
  user = config.users.users.${cfg.user};
  gid = toString config.users.groups.${user.group}.gid;
  settingsFormat = pkgs.formats.json { };
  configDir = "${user.home}/.config";
  stateDir = "${configDir}/shelley";
  # at the literal /exe.dev/shelley.json path — part of the platform surface
  configTree = pkgs.runCommand "shelley-config" { } ''
    install -D ${settingsFormat.generate "shelley.json" cfg.settings} $out/exe.dev/shelley.json
  '';
in
{
  options.services.shelley = {
    enable = lib.mkEnableOption "the Shelley coding agent, supervised by s6";
    # nixpkgs has no shelley; default to the one packaged in this repo.
    package = lib.mkOption {
      type = lib.types.package;
      default = import ../../../packages/shelley { inherit pkgs; };
      defaultText = lib.literalExpression "the shelley packaged in packages/shelley";
      description = "Shelley package (must expose a main program).";
    };
    user = lib.mkOption {
      type = lib.types.str;
      description = "Account to run Shelley as; declare it in users.users.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 9999;
      description = "Port Shelley serves on.";
    };
    settings = lib.mkOption {
      type = settingsFormat.type;
      default = { };
      description = "Shelley configuration (the -config JSON), e.g. llm_gateway.";
    };
    requireHeader = lib.mkOption {
      type = lib.types.str;
      default = "X-Exedev-Userid";
      description = "HTTP header Shelley requires on every request.";
    };
  };

  config = lib.mkIf cfg.enable {
    s6.services.shelley.run = ''
      mkdir -p ${stateDir}
      chown ${toString user.uid}:${gid} ${configDir} ${stateDir}
      # s6-setuidgid resolves the user from /etc/passwd, drops uid/gid, and
      # initializes supplementary groups — the s6-native way to run as a user.
      exec /command/s6-setuidgid ${cfg.user} \
        env \
          HOME=${user.home} \
          USER=${cfg.user} \
          SHELL=/bin/sh \
          XDG_CONFIG_HOME=${configDir} \
          PATH=/bin:/sbin:/usr/bin \
          SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
          GIT_SSL_CAINFO=/etc/ssl/certs/ca-bundle.crt \
        ${lib.getExe cfg.package} \
          -config /exe.dev/shelley.json \
          -db ${stateDir}/shelley.db \
          serve -port ${toString cfg.port} -require-header ${cfg.requireHeader}
    '';

    image.rootPaths = [ configTree ];
    image.packages = [ cfg.package ];
    image.exposedPorts.tcp = [ cfg.port ];
    # read by exe.dev at VM creation (enables Shelley + its UI icon)
    image.labels."exe.dev/install-shelley" = "true";
  };
}
