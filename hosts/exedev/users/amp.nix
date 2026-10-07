{ pkgs, inputs, ... }:
let
  home = "/var/lib/amp";
  # amp-cli is unfree; allow just it. unstable for a fresher build.
  amp =
    (import inputs.nixpkgs-unstable {
      inherit (pkgs.stdenv.hostPlatform) system;
      config.allowUnfreePredicate = p: pkgs.lib.getName p == "amp-cli";
    }).amp-cli;
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
      # serves the home plus git checkouts found under it.
      cd ${home}
      exec /command/s6-setuidgid amp \
        env \
          HOME=${home} \
          USER=amp \
          SHELL=/bin/sh \
          PATH=/etc/profiles/per-user/amp/bin:/nix/var/nix/profiles/default/bin:/bin:/sbin:/usr/bin \
          SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
          NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
          NODE_EXTRA_CA_CERTS=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
        ${amp}/bin/amp --no-tui \
          --runner-id computer \
          --discover-dirs \
          --discover-depth 3
    '';
  };
}
