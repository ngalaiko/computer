{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  rex = inputs.rex.packages.${pkgs.stdenv.hostPlatform.system}.default;
  accounts = pkgs.writeText "rex-accounts.json" (
    builtins.toJSON {
      version = 1;
      accounts.nikita.principals = [ "tailscale:ngalaiko@github" ];
    }
  );
in
{
  # Provision this root-readable file outside Nix; never put the token in the
  # flake or store. It is also needed on the machine fetching the flake inputs.
  nix.settings.netrc-file = "/etc/nix/rex.netrc";
  exedev.backup.paths = [ "/etc/nix/rex.netrc" ];

  environment.systemPackages = [ rex ];
  security.pam.services.rex-login-server.startSession = true;

  # Use the existing tailnet node, not the public Funnel on port 443. The login
  # server authorizes the specific principal above even though the node is tagged.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 7297 ];

  systemd.services.rex-login-server = {
    description = "Rex remote login server";
    wantedBy = [ "multi-user.target" ];
    requires = [ "tailscaled.service" ];
    after = [ "tailscaled.service" ];
    environment.TERMINFO_DIRS = "${rex}/share/terminfo:${pkgs.ncurses}/share/terminfo";
    serviceConfig = {
      ExecStart = lib.concatStringsSep " " [
        "${lib.getExe rex} login-server"
        "--listen unix:///run/rex/login-server.sock"
        "--accounts ${accounts}"
        "--runtime-root /run/rex"
        "--log-format text"
        "--pam-service rex-login-server"
        "--extra-listen tailnet://:7297"
      ];
      RuntimeDirectory = "rex";
      # Per-account servers and their sessions survive login-server restarts.
      RuntimeDirectoryPreserve = "restart";
      KillMode = "process";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
