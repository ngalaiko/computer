{ ... }:
{
  # SSH keys live in the Secure Enclave via Secretive
  # (https://github.com/maxgoedjen/secretive), which serves them from its own
  # ssh-agent socket. The auth+signing key is created in the Secretive GUI with
  # "Authenticate before use" OFF: the private key never leaves the enclave and
  # can't be exported, yet no Touch ID prompt fires per use. git and jj shell
  # out to ssh and inherit this agent for auth; jj's ssh-keygen signing reaches
  # the same key via SSH_AUTH_SOCK (see home/jj.nix).
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."*" = {
      IdentityAgent = "~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh";
    };
  };

  # ssh-keygen (jj's signing backend) reads SSH_AUTH_SOCK, not ssh_config, so it
  # needs the Secretive socket in the environment to sign with the enclave key.
  programs.fish.shellInit = ''
    set --global --export SSH_AUTH_SOCK "$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh"
  '';
}
