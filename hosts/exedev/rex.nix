{ inputs, ... }:
{
  imports = [ inputs.rex.nixosModules.default ];

  # Provision this root-readable file outside Nix; never put the token in the
  # flake or store. It is also needed on the machine fetching the flake inputs.
  nix.settings.netrc-file = "/etc/nix/rex.netrc";
  exedev.backup.paths = [ "/etc/nix/rex.netrc" ];

  # Use the existing tailnet node, not the public Funnel on port 443. The login
  # server authorizes the specific principal above even though the node is tagged.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 7297 ];

  services.rex.loginServer = {
    enable = true;
    accounts.nikita.principals = [ "tailscale:ngalaiko@github" ];
    extraListen = [ "tailnet://:7297" ];
  };
}
