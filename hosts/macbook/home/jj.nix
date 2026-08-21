{ lib, ... }:
{
  # Sublime Merge is a mac app
  programs.jujutsu.settings.ui.merge-editor = "smerge";

  # Sign commits with the Secure Enclave ecdsa-sk key (see ssh.nix), overriding
  # the ed25519 default in ../../../home/jj.nix — only this host has an enclave.
  programs.jujutsu.settings.signing.key = lib.mkForce "~/.ssh/id_ecdsa_sk_rk.pub";
}
