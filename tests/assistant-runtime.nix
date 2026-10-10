{ pkgs, inputs }:
let
  config =
    (import ../modules/exedev {
      inherit pkgs;
      specialArgs = { inherit inputs; };
    }).eval
      ../hosts/exedev;
  profile = pkgs.buildEnv {
    name = "amp-runtime-check-profile";
    paths = config.users.users.amp.packages;
    pathsToLink = [ "/bin" ];
  };
in
pkgs.runCommand "assistant-runtime-check"
  {
    nativeBuildInputs = [
      profile
      pkgs.bash
    ];
  }
  ''
    set -euo pipefail
    export HOME="$TMPDIR/home"
    amp-runtime-setup
    test "$(readlink "$HOME/.config/amp/AGENTS.md")" = /etc/amp/AGENTS.md
    test "$(readlink "$HOME/.config/amp/skills")" = /etc/amp/skills
    test "$(stat -c %a "$HOME/memory")" = 700
    # Custom instructions and skill directories survive repeated setup.
    rm "$HOME/.config/amp/AGENTS.md" "$HOME/.config/amp/skills"
    printf 'private instructions\n' > "$HOME/.config/amp/AGENTS.md"
    mkdir "$HOME/.config/amp/skills"
    touch "$HOME/.config/amp/skills/custom"
    amp-runtime-setup
    test "$(cat "$HOME/.config/amp/AGENTS.md")" = 'private instructions'
    test -f "$HOME/.config/amp/skills/custom"

    . ${config.environment.etc."amp/runtime.sh".source}
    test "$TZ" = Europe/Stockholm
    test "$ASSISTANT_MEMORY_DIR" = /var/lib/amp/memory
    test "$OBSIDIAN_VAULT_PATH" = /home/nikita/Vault
    himalaya --version | grep -q 'himalaya v1.2.0 '
    icloud-mail --version | grep -q 'himalaya v1.2.0 '
    icloud-calendar --help >/dev/null
    sops --version >/dev/null
    age --version >/dev/null
    bash -n "$(command -v gh-app)"

    export AGENT_BROWSER_SESSION="runtime-check-$$"
    trap 'agent-browser close >/dev/null' EXIT
    agent-browser open 'data:text/html,<title>Runtime ready</title><p>Pinned browser works</p>'
    test "$(agent-browser get title)" = 'Runtime ready'
    test "$(agent-browser get text body)" = 'Pinned browser works'
    touch "$out"
  ''
