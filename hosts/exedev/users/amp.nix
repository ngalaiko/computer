{
  pkgs,
  inputs,
  lib,
  ...
}:
let
  home = "/var/lib/amp";
  project = "${home}/assistant";
  assistantTools = inputs.assistant.devShells.${pkgs.stdenv.hostPlatform.system}.default;
  assistantPkgs = inputs.assistant.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  runtimeEnvironment = {
    TZ = "Europe/Stockholm";
    ASSISTANT_MEMORY_DIR = "${home}/memory";
    OBSIDIAN_VAULT_PATH = "/home/nikita/Vault";
    ASSISTANT_SECRETS_FILE = "${home}/.config/assistant/secrets.json";
    SOPS_AGE_KEY_FILE = "${home}/.config/assistant/age-key.txt";
    HIMALAYA_CONFIG = "${home}/.config/himalaya/config.toml";
    AGENT_BROWSER_EXECUTABLE_PATH = assistantTools.AGENT_BROWSER_EXECUTABLE_PATH;
    FONTCONFIG_FILE = assistantPkgs.makeFontsConf {
      fontDirectories = [ assistantPkgs.dejavu_fonts ];
    };
  };
  runtimeSettings = pkgs.writeText "amp-runtime.sh" (
    lib.concatStrings (
      lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}\n") runtimeEnvironment
    )
    + ''
      if [ -f ${home}/.config/assistant/runtime.sh ]; then
        set -a
        . ${home}/.config/assistant/runtime.sh
        set +a
      fi
    ''
  );
  mail = pkgs.writeShellScriptBin "icloud-mail" ''
    set -eu
    . ${runtimeSettings}
    exec ${
      lib.getExe (lib.findFirst (p: p.pname or "" == "himalaya") null assistantTools.nativeBuildInputs)
    } "$@"
  '';
  calendar = pkgs.writeShellScriptBin "icloud-calendar" ''
    set -eu
    . ${runtimeSettings}
    exec ${
      inputs.assistant.packages.${pkgs.stdenv.hostPlatform.system}.calendar
    }/bin/assistant-calendar "$@"
  '';
  github = pkgs.writeShellApplication {
    name = "gh-app";
    runtimeInputs = [
      pkgs.python3
      pkgs.openssl
    ];
    text = ''
      # shellcheck source=/dev/null
      . ${runtimeSettings}
      exec python3 ${home}/.config/gh-app/auth.py "$@"
    '';
  };
  setup = pkgs.writeShellScriptBin "amp-runtime-setup" ''
    set -eu
    umask 077
    mkdir -p "$HOME/.config/amp" "$HOME/memory"
    for name in AGENTS.md skills; do
      target=$HOME/.config/amp/$name
      if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        ln -s /etc/amp/$name "$target"
      fi
    done
  '';
  # amp-cli is unfree; allow just it. unstable for a fresher build.
  amp =
    (import inputs.nixpkgs-unstable {
      inherit (pkgs.stdenv.hostPlatform) system;
      config.allowUnfreePredicate = p: pkgs.lib.getName p == "amp-cli";
    }).amp-cli;
  runner = pkgs.writeShellScript "assistant-amp-runner" ''
    set -eu
    # Load user-owned configuration after dropping privileges.
    envfile=${home}/.config/amp-runner/env
    if [ ! -f "$envfile" ]; then
      echo "amp-runner: $envfile missing; place AMP_API_KEY=... (see README). Retrying." >&2
      sleep 30
      exit 1
    fi
    set -a
    . "$envfile"
    set +a
    if [ -z "''${AMP_API_KEY:-}" ]; then
      echo "amp-runner: AMP_API_KEY unset in $envfile. Retrying." >&2
      sleep 30
      exit 1
    fi
    . ${runtimeSettings}
    mkdir -p ${project}
    cd ${project}
    # Preserve existing files and local edits; never force checkout.
    if [ ! -e .git ]; then
      git init
      git remote add origin https://github.com/ngalaiko/assistant.git
    fi
    case "$(git config --get remote.origin.url)" in
      https://github.com/ngalaiko/assistant|https://github.com/ngalaiko/assistant.git|git@github.com:ngalaiko/assistant.git) ;;
      *) echo "amp-runner: ${project} is not the assistant repository; refusing to start." >&2; exit 1 ;;
    esac
    if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
      git fetch origin ${inputs.assistant.rev}
      git checkout -b main FETCH_HEAD
    fi
    # Amp uses its starting directory as the default project root.
    exec ${amp}/bin/amp --no-tui --runner-id computer --remote-control-terminal
  '';
in
{
  # Amp runner account: threads started on ampcode.com run here. Unprivileged
  # (no sudo, not nix-trusted), like the assistant, which caps what a thread can
  # do on the box.
  users.users.amp = {
    uid = 2002;
    group = "amp";
    inherit home;
    createHome = true;
    shell = "/bin/sh";
    description = "Amp runner";
    environment = lib.mapAttrs (_: toString) runtimeEnvironment;
    packages =
      assistantTools.nativeBuildInputs
      ++ (with pkgs; [
        amp
        assistantPkgs.chromium
        mail
        calendar
        github
        setup
        nodejs_22
        git
        jujutsu
        fd
      ]);
  };
  users.groups.amp.gid = 2002;

  environment.etc."amp/runtime.sh".source = runtimeSettings;
  environment.etc."amp/AGENTS.md".text = ''
    # Assistant runtime on computer

    Follow @${inputs.assistant}/AGENTS.md and each repository's instructions.
    Skills are deployed from the same locked assistant revision.

    - User timezone: Europe/Stockholm; the host clock is UTC.
    - Assistant memory: ${home}/memory. Read relevant notes before asking for
      information already recorded. The shared Obsidian vault is /home/nikita/Vault;
      it is distinct from assistant memory. Sync and backups are infrastructure.
    - Runtime defaults: /etc/amp/runtime.sh. Private overrides:
      ${home}/.config/assistant/runtime.sh. Source the defaults to discover overridden
      paths; runner threads inherit them automatically.
    - Mail: /etc/profiles/per-user/amp/bin/icloud-mail (Himalaya arguments).
    - Calendar: /etc/profiles/per-user/amp/bin/icloud-calendar (assistant-calendar arguments).
    - GitHub: /etc/profiles/per-user/amp/bin/gh-app (gh arguments). Authentication
      uses the existing private ${home}/.config/gh-app/auth.py and GitHub App key.
    - Tools on PATH are deployment-pinned, independent of edits in ${project}.

    Never print credentials, keys, tokens, or whole environment/configuration dumps.
    Access does not authorize sending, changing events, pushing, or deploying.
  '';
  image.rootPaths = [
    (pkgs.runCommand "amp-skills" { } ''
      mkdir -p $out/etc/amp
      ln -s ${inputs.assistant}/.agents/skills $out/etc/amp/skills
    '')
  ];

  # /amp/* on the public port. The ingress module puts caddy on Amp's PATH
  # and seeds a user-owned ~/.caddy/Caddyfile, reloadable without root.
  services.ingress.tenants.amp = {
    upstreamPort = 8084;
  };

  # checkouts, amp config, and the runner env file all live under the home.
  services.backup.paths = [ home ];

  s6.services.amp-runtime-setup = {
    type = "oneshot";
    reactivate = true;
    dependencies = [
      "base"
      "backup-restore"
    ];
    run = ''
      exec /command/s6-setuidgid amp env HOME=${home} ${setup}/bin/amp-runtime-setup
    '';
  };

  s6.services.amp-runner = {
    dependencies = [
      "base"
      # wait for the restore so the env file and checkouts are present.
      "backup-restore"
      "amp-runtime-setup"
    ];
    run = ''
      exec /command/s6-setuidgid amp \
        env \
          HOME=${home} \
          USER=amp \
          SHELL=/bin/sh \
          PATH=/etc/profiles/per-user/amp/bin:/nix/var/nix/profiles/default/bin:/bin:/sbin:/usr/bin \
          SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
          NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
          NODE_EXTRA_CA_CERTS=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
        ${runner}
    '';
  };
}
