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

  # ssh access is via tailscale ssh; no sshd server ships.
  security.sudo.enable = true;

  nix.trustedUsers = [ name ];

  services.backup.paths = [
    # hand-generated per-machine key; preserved by backup.
    "${home}/.ssh"
    # per-app state the image can't regenerate: atuin's history db + sync
    # identity (host_id/key), fish history, etc. Home-manager owns the dotfiles
    # (baked into the image under ~/.config), so nothing here shadows them.
    "${home}/.local/share"
    # ingress routes for /nikita/* (see services.ingress below).
    "${home}/.caddy"
  ];

  # /nikita/* on the public port.
  services.ingress.tenants.nikita = {
    upstreamPort = 8082;
  };

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
