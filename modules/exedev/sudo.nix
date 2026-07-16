{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.security.sudo;

  # store modes normalize to 0444/0555 — no setuid, sudoers world-readable —
  # so both are baked via fakeroot instead.
  sudoers = pkgs.writeText "sudoers" ''
    root   ALL=(ALL:ALL) SETENV: ALL
    %wheel ALL=(ALL:ALL) NOPASSWD:SETENV: ALL
  '';

  # accounts are passwordless, so permit is the whole stack.
  pamSudo = ''
    auth     sufficient ${pkgs.pam}/lib/security/pam_permit.so
    account  required   ${pkgs.pam}/lib/security/pam_permit.so
    session  required   ${pkgs.pam}/lib/security/pam_permit.so
  '';
in
{
  options.security.sudo.enable = lib.mkEnableOption "sudo; members of wheel get passwordless root";

  config = lib.mkIf cfg.enable {
    users.groups.wheel.gid = 1;

    # the plugin loads from sudo's store path, so it must ship (registered).
    image.packages = [ pkgs.sudo ];

    # fakeroot fakes ownership only for explicit chowns.
    image.fakeRootCommands = ''
      mkdir -p ./bin ./etc
      rm -f ./bin/sudo
      install -m 4755 -o 0 -g 0 ${pkgs.sudo}/bin/sudo ./bin/sudo
      install -m 0440 -o 0 -g 0 ${sudoers} ./etc/sudoers
    '';

    environment.etc."pam.d/sudo".text = pamSudo;
    environment.etc."pam.d/sudo-i".text = pamSudo;
  };
}
