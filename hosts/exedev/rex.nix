{ inputs, ... }:
{
  imports = [ inputs.rex.nixosModules.default ];

  # Use the existing tailnet node, not the public Funnel on port 443. The login
  # server authorizes the specific principal above even though the node is tagged.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 7297 ];

  services.rex.loginServer = {
    enable = true;
    accounts.nikita.principals = [ "tailscale:ngalaiko@github" ];
    extraListen = [ "tailnet://:7297" ];
    tailscaleServe = {
      enable = true;
      httpsPort = 8443;
    };
  };

  # The public ingress unit resets Serve mappings before recreating the Funnel.
  systemd.services.rex-tailscale-serve = {
    requires = [ "tailscale-serve.service" ];
    after = [ "tailscale-serve.service" ];
    partOf = [ "tailscale-serve.service" ];
  };
}
