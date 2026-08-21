{ pkgs, ... }:
let
  # jj's ssh signing backend (see ../../../home/jj.nix) invokes ssh-keygen and
  # expects a private key file, but the Secretive key lives only in the Secure
  # Enclave and is reachable solely through its ssh-agent. Wrap ssh-keygen to
  # add -U (sign with the agent-held key matching the public key) so jj still
  # sees a plain "ssh-keygen". -U is only valid for `-Y sign`; jj reuses the
  # same program to verify (`-Y verify`), where -U errors, so add it only when
  # signing. The socket comes from SSH_AUTH_SOCK, set in home/ssh.nix.
  sign-with-agent = pkgs.writeShellScript "jj-ssh-keygen-agent-sign" ''
    case " $* " in
      *"-Y sign"*) exec ${pkgs.openssh}/bin/ssh-keygen -U "$@" ;;
      *) exec ${pkgs.openssh}/bin/ssh-keygen "$@" ;;
    esac
  '';
in
{
  # Sublime Merge is a mac app
  programs.jujutsu.settings.ui.merge-editor = "smerge";

  # Sign commits with the Secretive Secure Enclave key (see home/ssh.nix),
  # created in the Secretive GUI with "Authenticate before use" OFF so signing
  # never prompts for Touch ID. The public key is exported to this path from
  # Secretive (Copy Public Key → save as ~/.ssh/id_secretive.pub).
  programs.jujutsu.settings.signing.key = "~/.ssh/id_secretive.pub";
  programs.jujutsu.settings.signing.backends.ssh.program = toString sign-with-agent;
}
