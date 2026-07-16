# the login account: exe.dev shells in as this user (see the login-user
# label in ../default.nix); exe-init requires workingDir to exist.
{ ... }:
let
  name = "exedev";
  home = "/home/${name}";
in
{
  image.workingDir = home;

  services.sshd = {
    enable = true;
    authorizedKeys.user = name;
  };

  users.users.${name} = {
    uid = 1000;
    group = name;
    inherit home;
    createHome = true;
    shell = "/bin/sh";
    description = "exe.dev user";
  };
  users.groups.${name}.gid = 1000;
}
