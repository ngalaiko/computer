{ pkgs, ... }:
let
  # pi (the coding agent) is an npm CLI, packaged from its published tarball.
  # MIT, all-JS deps, so it builds against the pinned nixpkgs directly (no
  # unstable / allowUnfree, unlike cptr).
  pi = import ../../../packages/pi { inherit pkgs; };
in
{
  users.users.assistant = {
    uid = 2001;
    group = "assistant";
    home = "/var/lib/assistant";
    createHome = true;
    shell = "/bin/sh";
    description = "Assistant (pi coding agent)";

    # pi plus the tools it drives (git, gh, ripgrep, …) and a node runtime for
    # its TypeScript extensions / any node subprocesses. The account is
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
      uv
    ];
  };
  users.groups.assistant.gid = 2001;

  services.backup = {
    enable = true;
    # pi's config, auth (provider keys), session history, and the agent
    # workspace all live under the home.
    paths = [ "/var/lib/assistant" ];
  };
}
