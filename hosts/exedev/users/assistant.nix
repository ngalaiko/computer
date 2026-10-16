{ pkgs, ... }:
let
  # pi (the coding agent) is an npm CLI, packaged from its published tarball.
  # MIT, all-JS deps, so it builds against the pinned nixpkgs directly.
  pi = import ../../../packages/pi { inherit pkgs; };
in
{
  users.users.assistant = {
    uid = 2001;
    group = "assistant";
    home = "/var/lib/assistant";
    createHome = true;
    isSystemUser = true;
    shell = pkgs.bashInteractive;
    description = "Assistant (pi coding agent)";

    # pi plus the tools it drives (git, gh, ripgrep, Chromium, …) and a node
    # runtime for its TypeScript extensions / any node subprocesses. The account is
    # unprivileged (no sudo, not nix-trusted), which caps what the agent can do
    # on the box; BYOK provider keys are supplied at runtime, not baked in.
    packages = with pkgs; [
      pi
      nodejs_22
      git
      gh
      jq
      ripgrep
      curl
      coreutils
      fd # pi checks for fd at interactive startup and uses it for file autocomplete/find.
      ledger
      himalaya # CLI for the assistant's authorized iCloud Mail access.
      chromium
    ];
  };
  users.groups.assistant.gid = 2001;

  # /assistant/* on the public port, served by the assistant's own caddy (the
  # ingress module also puts caddy on the assistant PATH so the agent can
  # validate and reload ~/.caddy/Caddyfile). It fronts wherenow at
  # /assistant/wherenow/* -> the wherenow backend on loopback 8085: the root
  # caddy strips /assistant, this handle strips /wherenow, so wherenow sees
  # /api/*. The trailing 404 leaves the rest of /assistant/* the agent's to
  # self-manage. Public, but every wherenow write needs the bearer TOKEN.
  #
  # NB: `routes` is only the SEED for the tenant's Caddyfile. A box that already
  # has ~assistant/.caddy/Caddyfile keeps its copy, so on first rollout add this
  # handle there by hand (or delete the file to let it re-seed) then reload caddy.
  services.ingress.tenants.assistant = {
    upstreamPort = 8083;
    routes = ''
      handle_path /wherenow/* {
        reverse_proxy 127.0.0.1:8085
      }
      respond "assistant: no routes configured yet" 404
    '';
  };

  # pi's config, auth (provider keys), session history, and the agent workspace
  # all live under the home. This also covers the runtime-installed pi plugins
  # (~/.pi/agent/npm), so a recreated machine restores them.
  exedev.backup.paths = [ "/var/lib/assistant" ];
}
