{ pkgs, inputs, ... }:
let
  name = "nikita";
  home = "/home/${name}";
  hm = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { inherit inputs; };
    modules = [
      ../../../home
      {
        home.username = name;
        home.homeDirectory = home;
        programs.fish.interactiveShellInit = "set --global prompt_host exedev";
      }
    ];
  };
in
{
  image.workingDir = home;

  # ssh is via tailscale now; openssh kept but disabled.
  services.sshd = {
    enable = false;
    authorizedKeys.user = name;
  };

  security.sudo.enable = true;

  nix.trustedUsers = [ name ];

  services.backup.paths = [
    # hand-generated per-machine key; preserved by backup.
    "${home}/.ssh"
    # atuin shell history + sync identity (host_id/key), so a recreated VM
    # keeps its history instead of registering as a fresh atuin host.
    "${home}/.local/share/atuin"
  ];

  users.users.${name} = {
    uid = 1000;
    group = name;
    inherit home;
    createHome = true;
    shell = "/etc/profiles/per-user/${name}/bin/fish";
    description = "Nikita Galaiko";
    packages = [ hm.config.home.path ];
    files = hm.config.home-files;
  };
  users.groups.${name}.gid = 1000;
  users.groups.wheel.members = [ name ];
}
