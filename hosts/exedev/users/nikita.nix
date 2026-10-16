{ pkgs, ... }:
let
  name = "nikita";
  home = "/home/${name}";
in
{
  imports = [ ./nikita/vault.nix ];

  exedev.image.workingDir = home;

  nix.settings.trusted-users = [ name ];

  # the whole home, so nothing hand-made is lost on recreation; home-manager
  # re-links the dotfiles over the restored copies.
  exedev.backup.paths = [ home ];

  # /nikita/* on the public port.
  services.ingress.tenants.nikita = {
    upstreamPort = 8082;
  };

  programs.fish.enable = true;

  users.users.${name} = {
    uid = 1000;
    group = name;
    isNormalUser = true;
    inherit home;
    shell = pkgs.fish;
    description = "Nikita Galaiko";
    extraGroups = [ "wheel" ];
  };
  users.groups.${name}.gid = 1000;

  # link over the restored home, not under it.
  systemd.services."home-manager-${name}" = {
    wants = [ "backup-restore.service" ];
    after = [ "backup-restore.service" ];
  };

  home-manager.users.${name} = {
    imports = [ ../../../home ];
    programs.fish.interactiveShellInit = "set --global prompt_host computer";
  };
}
