{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;

  withPackages = lib.filterAttrs (_: u: u.packages != [ ]) config.users.users;
  withEnv = lib.filterAttrs (_: u: u.environment != { }) config.users.users;
  withFiles = lib.filterAttrs (_: u: u.files != null) config.users.users;

  profiles = pkgs.runCommand "per-user-profiles" { } (
    ''
      mkdir -p $out/etc/profiles/per-user
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (name: u: ''
        ln -s ${
          pkgs.buildEnv {
            name = "user-profile-${name}";
            paths = u.packages;
            pathsToLink = [
              "/bin"
              "/share"
            ];
          }
        } $out/etc/profiles/per-user/${name}
      '') withPackages
    )
  );

  exports =
    env: lib.concatStrings (lib.mapAttrsToList (k: v: "  export ${k}=${lib.escapeShellArg v}\n") env);
in
{
  options.users.users = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          packages = mkOption {
            type = types.listOf types.package;
            default = [ ];
            description = "Per-user packages, linked at /etc/profiles/per-user/<name> and put on the login-shell PATH (cf. NixOS users.users.<name>.packages).";
          };
          environment = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "Per-user environment: exported by login shells; service modules that run as the user inject it too (cf. services.cptr).";
          };
          files = mkOption {
            type = types.nullOr types.package;
            default = null;
            description = "Tree copied (dereferenced) into the user's home at build, owned by the user; its closure is shipped for store paths referenced from file contents.";
          };
        };
      }
    );
  };

  config = {
    image.rootPaths = lib.mkIf (withPackages != { }) [ profiles ];
    nix.registerPaths =
      lib.optionals (withPackages != { }) [ profiles ] ++ lib.mapAttrsToList (_: u: u.files) withFiles;

    # dereferenced, so baked homes stay editable at runtime; store paths
    # referenced from file contents ship via registerPaths below.
    image.fakeRootCommands = lib.concatStrings (
      lib.mapAttrsToList (
        _: u:
        lib.optionalString (u.files != null) ''
          mkdir -p .${u.home}
          cp -RL ${u.files}/. .${u.home}/
          chmod -R u+w .${u.home}
          chown -R ${toString u.uid}:${toString config.users.groups.${u.group}.gid} .${u.home}
        ''
      ) config.users.users
    );

    # sorts before nix.sh, so nix profiles stay ahead of the per-user profile.
    environment.etc."profile.d/home.sh".text = ''
      export PATH="/etc/profiles/per-user/$(id -un)/bin:$PATH"
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (
        name: u:
        ''
          if [ "$(id -un)" = "${name}" ]; then
        ''
        + exports u.environment
        + ''
          fi
        ''
      ) withEnv
    );
  };
}
