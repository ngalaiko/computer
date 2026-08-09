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

    # setuid sudo + 0440 sudoers: the store normalizes these modes away, so bake
    # them via the shared $root fixups — asserted at image build (fakeroot) AND on
    # every in-place activate (real root). Missing this on a switch would drop the
    # setuid bit and lock wheel out of passwordless root.
    image.activationFixups = ''
      mkdir -p "$root/bin" "$root/etc"
      rm -f "$root/bin/sudo"
      install -m 4755 -o 0 -g 0 ${pkgs.sudo}/bin/sudo "$root/bin/sudo"
      install -m 0440 -o 0 -g 0 ${sudoers} "$root/etc/sudoers"
    '';

    environment.etc."pam.d/sudo".text = pamSudo;
    environment.etc."pam.d/sudo-i".text = pamSudo;
  };
}
