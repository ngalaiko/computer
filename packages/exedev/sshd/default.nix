# OpenSSH server + sshd_config, plus the sshd-keygen and exedev-authorized-keys
# scripts its s6 oneshots run.
{ pkgs }:
{
  packages = [ pkgs.openssh ];
  rootfs = ./rootfs;
}
