{ pkgs, inputs, ... }:
let
  home = "/var/lib/amp";
  project = "${home}/assistant";
  # amp-cli is unfree; allow just it. unstable for a fresher build.
  amp =
    (import inputs.nixpkgs-unstable {
      inherit (pkgs.stdenv.hostPlatform) system;
      config.allowUnfreePredicate = p: pkgs.lib.getName p == "amp-cli";
    }).amp-cli;
  runner = pkgs.writeShellScript "assistant-amp-runner" ''
    set -eu
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
      git fetch origin
      git remote set-head origin --auto
      branch=$(git symbolic-ref --short refs/remotes/origin/HEAD)
      git checkout -b "''${branch#origin/}" --track origin/HEAD
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
    packages = with pkgs; [
      amp
      nodejs_22
      git
      jujutsu
      gh
      jq
      ripgrep
      fd
      curl
      coreutils
    ];
  };
  users.groups.amp.gid = 2002;

  # /amp/* on the public port. The ingress module puts caddy on Amp's PATH
  # and seeds a user-owned ~/.caddy/Caddyfile, reloadable without root.
  services.ingress.tenants.amp = {
    upstreamPort = 8084;
  };

  # checkouts, amp config, and the runner env file all live under the home.
  services.backup.paths = [ home ];

  s6.services.amp-runner = {
    dependencies = [
      "base"
      # wait for the restore so the env file and checkouts are present.
      "backup-restore"
    ];
    run = ''
      # AMP_API_KEY stays out of the repo and the Nix store: it lives in a
      # runtime env file under the backed-up home (see README), exported so it
      # never appears in argv.
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
