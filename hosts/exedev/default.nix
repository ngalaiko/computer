{ pkgs, ... }:
{
  imports = [ ./users ];

  image = {
    name = "computer.exe";
    labels = {
      "org.opencontainers.image.title" = "computer.exe";
      "org.opencontainers.image.description" = "exe.dev image: s6-overlay and Tailscale SSH";
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
    # One tailnet node, `computer`: ssh + the public ingress funnel on its own
    # name, rebuilt on every boot.
    nodes.computer = {
      ssh = true;
      serve = [
        # public path-routed ingress via node Funnel:
        # https://computer.<tailnet>.ts.net/<tenant>/. World-reachable with NO
        # auth — unlike the exe.dev-shared 8080, which exe.dev gates. Node-named,
        # so this URL can churn when the machine is recreated; exe.dev's share
        # stays the stable public path. Only configured tenants are served.
        {
          target = "localhost:8080";
          port = 443;
          funnel = true;
        }
      ];
    };
  };

  # tenants registered per-user in hosts/exedev/users/*.nix.
  services.ingress.enable = true;
  nix-ld.enable = true;

  # fish reads no /etc/profile; wire the nix profiles for fish logins.
  environment.etc."fish/config.fish".text = ''
    fish_add_path --global --move --path \
      "$HOME/.nix-profile/bin" \
      /etc/profiles/per-user/(whoami)/bin \
      /nix/var/nix/profiles/default/bin
  '';
}
