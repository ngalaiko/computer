{ ... }:
{
  # SSH keys live in the Secure Enclave (created once with:
  #   sc_auth create-ctk-identity -l ssh -k p-256-ne -t bio
  #   cd ~/.ssh && ssh-keygen -w /usr/lib/ssh-keychain.dylib -K -N "")
  # Apple's ssh-keychain.dylib exposes the enclave key to OpenSSH as an
  # ecdsa-sk key; Touch ID authorizes each use. git and jj shell out to ssh,
  # so they inherit this for auth with no agent or GUI app.
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."*" = {
      SecurityKeyProvider = "/usr/lib/ssh-keychain.dylib";
      IdentityFile = "~/.ssh/id_ecdsa_sk_rk";
    };
  };

  # ssh-keygen (used by jj's ssh signing backend) does not read ssh_config, so
  # it needs the security-key provider via this env var to sign with the
  # enclave key. Set in launchd too if you ever sign from a GUI-launched app:
  #   launchctl setenv SSH_SK_PROVIDER /usr/lib/ssh-keychain.dylib
  programs.fish.shellInit = ''
    set --global --export SSH_SK_PROVIDER "/usr/lib/ssh-keychain.dylib"
  '';
}
