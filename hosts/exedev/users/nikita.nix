{ ... }:
let
  name = "nikita";
  home = "/home/${name}";
in
{
  image.workingDir = home;

  services.sshd = {
    enable = true;
    authorizedKeys.user = name;
  };

  security.sudo.enable = true;

  nix.trustedUsers = [ name ];

  users.users.${name} = {
    uid = 1000;
    group = name;
    inherit home;
    createHome = true;
    shell = "/bin/sh";
    description = "Nikita Galaiko";
  };
  users.groups.${name}.gid = 1000;
  users.groups.wheel.members = [ name ];
}
