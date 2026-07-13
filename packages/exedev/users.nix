# All users/groups + the static /etc/{passwd,group,shadow} generated from them.
# These override docker.nix's baked files, so root/nobody/nixbld1..32 must be
# re-declared here or multi-user Nix builds break (nixbld count tracks the
# pinned nix source's `lib.range 1 32`).
{ pkgs }:
let
  inherit (pkgs) lib;
  nologin = "${pkgs.shadow}/bin/nologin";

  nixbld = lib.listToAttrs (
    map (n: {
      name = "nixbld${toString n}";
      value = {
        uid = 30000 + n;
        gid = 30000;
        home = "/var/empty";
        shell = "/bin/false";
        description = "Nix build user ${toString n}";
        locked = true;
      };
    }) (lib.range 1 32)
  );

  # locked=true → shadow '!' (no login); else '*' (pubkey ok). sshd with
  # `UsePAM no` refuses even pubkey for a locked account, so exedev stays unlocked.
  users = {
    root = {
      uid = 0;
      gid = 0;
      home = "/root";
      shell = "/bin/sh";
      description = "System administrator";
      locked = true;
    };
    nobody = {
      uid = 65534;
      gid = 65534;
      home = "/var/empty";
      shell = nologin;
      description = "Unprivileged account (don't use!)";
      locked = true;
    };
    exedev = {
      uid = 1000;
      gid = 1000;
      home = "/home/exedev";
      shell = "/bin/sh";
      description = "exe.dev user";
    };
    sshd = {
      uid = 30033;
      gid = 30033;
      home = "/var/empty";
      shell = nologin;
      description = "sshd privilege separation user";
    };
  }
  // nixbld;

  # group name -> gid; nixbld lists its build users as members (nix checks that).
  groups = {
    root = 0;
    tty = 5;
    users = 100;
    exedev = 1000;
    sshd = 30033;
    nixbld = 30000;
    nobody = 65534;
  };
  groupMembers = {
    nixbld = lib.attrNames nixbld;
  };

  passwdLine =
    name: u:
    "${name}:x:${toString u.uid}:${toString u.gid}:${u.description or ""}:${u.home or "/var/empty"}:${u.shell or "/bin/sh"}";
  shadowLine = name: u: "${name}:${if (u.locked or false) then "!" else "*"}:1::::::";
  groupLine =
    name: gid: "${name}:x:${toString gid}:${lib.concatStringsSep "," (groupMembers.${name} or [ ])}";

  join = f: attrs: lib.concatStringsSep "\n" (lib.mapAttrsToList f attrs) + "\n";
  passwd = join passwdLine users;
  shadow = join shadowLine users;
  group = join groupLine groups;
in
pkgs.runCommand "exedev-users" { } ''
  mkdir -p $out/etc $out/var/empty
  install -m0644 ${pkgs.writeText "passwd" passwd} $out/etc/passwd
  install -m0644 ${pkgs.writeText "group" group}   $out/etc/group
  install -m0640 ${pkgs.writeText "shadow" shadow} $out/etc/shadow
''
