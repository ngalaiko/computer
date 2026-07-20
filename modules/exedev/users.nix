{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;

  gidOf = u: config.users.groups.${u.group}.gid;

  passwdLine =
    name: u: "${name}:x:${toString u.uid}:${toString (gidOf u)}:${u.description}:${u.home}:${u.shell}";
  # locked → '!' (account disabled); else '*' (active, no stored password).
  shadowLine = name: u: "${name}:${if u.locked then "!" else "*"}:1::::::";
  groupLine = name: g: "${name}:x:${toString g.gid}:${lib.concatStringsSep "," g.members}";

  joinLines = f: attrs: lib.concatLines (lib.mapAttrsToList f attrs);

  # the default home for accounts without one (e.g. nobody).
  varEmpty = pkgs.runCommand "var-empty" { } ''
    mkdir -p $out/var/empty
  '';
in
{
  options.users = {
    users = mkOption {
      default = { };
      description = "System accounts, rendered into /etc/{passwd,shadow} (cf. NixOS users.users).";
      type = types.attrsOf (
        types.submodule {
          options = {
            uid = mkOption {
              type = types.int;
              description = "Numeric user id.";
            };
            group = mkOption {
              type = types.str;
              description = "Primary group name; must exist in users.groups.";
            };
            description = mkOption {
              type = types.str;
              default = "";
              description = "GECOS/comment field.";
            };
            home = mkOption {
              type = types.str;
              default = "/var/empty";
              description = "Home directory.";
            };
            shell = mkOption {
              type = types.str;
              default = "/bin/false";
              description = "Login shell.";
            };
            locked = mkOption {
              type = types.bool;
              default = false;
              description = "No login at all when true; otherwise password-less (pubkey ok).";
            };
            createHome = mkOption {
              type = types.bool;
              default = false;
              # exe.dev's init fails if image.workingDir is missing.
              description = "Bake the home dir into the image, owned by the user.";
            };
          };
        }
      );
    };

    groups = mkOption {
      default = { };
      description = "System groups, rendered into /etc/group.";
      type = types.attrsOf (
        types.submodule {
          options = {
            gid = mkOption {
              type = types.int;
              description = "Numeric group id.";
            };
            members = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Member user names.";
            };
          };
        }
      );
    };
  };

  config = {
    users.users = {
      root = {
        uid = 0;
        group = "root";
        home = "/root";
        shell = "/bin/sh";
        description = "System administrator";
        locked = true;
      };
      nobody = {
        uid = 65534;
        group = "nobody";
        description = "Unprivileged account (don't use!)";
        locked = true;
      };
    };
    users.groups = {
      root.gid = 0;
      users.gid = 100;
      nobody.gid = 65534;
    };

    environment.etc = {
      passwd.text = joinLines passwdLine config.users.users;
      group.text = joinLines groupLine config.users.groups;
      shadow = {
        text = joinLines shadowLine config.users.users;
        mode = "0640";
      };
    };

    image.rootPaths = [ varEmpty ];

    # store paths are root-owned; fakeroot bakes ownership (numeric ids only).
    image.fakeRootCommands = lib.concatStrings (
      lib.mapAttrsToList (
        _: u:
        lib.optionalString u.createHome ''
          mkdir -p .${u.home}
          chown ${toString u.uid}:${toString (gidOf u)} .${u.home}
        ''
      ) config.users.users
    );
  };
}
