{ pkgs, ... }:
{
  imports = [ ./users ];

  image = {
    name = "computer.exe";
    labels = {
      "org.opencontainers.image.title" = "computer.exe";
      "org.opencontainers.image.description" = "exe.dev image: s6-overlay, Tailscale SSH, and Hermes";
      "exe.dev/login-user" = "nikita";
    };
    packages = with pkgs; [
      bashInteractive
      coreutils-full
      findutils
      gnugrep
      gnused
      iproute2
      openssh # ssh client + ssh-keygen (git/jj signing); no sshd server
      procps
      tzdata
      util-linux
      curl
    ];
  };

  services.tailscale = {
    enable = true;
    hostname = "exedev";
  };

  # tenants registered per-user in hosts/exedev/users/*.nix.
  services.ingress.enable = true;

  # fish reads no /etc/profile; wire the nix profiles for fish logins.
  environment.etc."fish/config.fish".text = ''
    fish_add_path --global --move --path \
      "$HOME/.nix-profile/bin" \
      /etc/profiles/per-user/(whoami)/bin \
      /nix/var/nix/profiles/default/bin
  '';
}
