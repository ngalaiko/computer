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

  # The signing key path (~/.ssh/id_ed25519.pub) is set in the shared config
  # (../../../home/jj.nix). On this Mac only the public half sits on disk; the
  # private key is sealed in the Secure Enclave and reachable solely through
  # Secretive's ssh-agent (SSH_AUTH_SOCK, set in home/ssh.nix). The key was
  # created in the Secretive GUI with "Authenticate before use" OFF so signing
  # never prompts for Touch ID. The wrapper adds -U so ssh-keygen signs with the
  # agent-held key rather than reading a private key file.
  programs.jujutsu.settings.signing.backends.ssh.program = toString sign-with-agent;
}
