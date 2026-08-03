{ pkgs, ... }:
{
  imports = [ ./users ];

  image = {
    name = "computer.exe";
    labels = {
      "org.opencontainers.image.title" = "computer.exe";
      "org.opencontainers.image.description" =
        "exe.dev image: s6-overlay, Tailscale SSH, and Open WebUI Computer (cptr)";
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
    # name, and it also hosts the cptr dashboard as a Tailscale *Service*. Both
    # bind :443 but on different IPs (the node's own IP for the funnel, the
    # service VIP for the dashboard), rebuilt on every boot.
    nodes.computer = {
      ssh = true;
      # let the unprivileged cptr account read the LocalAPI (tailscale status /
      # funnel status) to report the current public hostname; writes stay
      # root-only. See the public-hostname skill.
      localApiReadable = true;
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
        # cptr dashboard as a stable Tailscale Service:
        # https://cptr.<tailnet>.ts.net/, tailnet-private. svc:cptr lives in the
        # tailnet policy (autoApprover + grant, see README), so the URL survives
        # this node re-registering as a fresh device on every recreation.
        {
          target = "localhost:9999";
          port = 443;
          service = "svc:cptr";
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
