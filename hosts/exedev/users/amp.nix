{
  pkgs,
  inputs,
  ...
}:
let
  home = "/var/lib/amp";
  # These are tool requirements, not private account or data-path configuration.
  toolEnvironment = {
    AGENT_BROWSER_EXECUTABLE_PATH = pkgs.lib.getExe pkgs.chromium;
    FONTCONFIG_FILE = toString (
      pkgs.makeFontsConf {
        fontDirectories = [ pkgs.dejavu_fonts ];
      }
    );
  };
  # amp-cli is unfree; allow just it. unstable for a fresher build.
  amp =
    (import inputs.nixpkgs-unstable {
      inherit (pkgs.stdenv.hostPlatform) system;
      config.allowUnfreePredicate = p: pkgs.lib.getName p == "amp-cli";
    }).amp-cli;
  runner = pkgs.writeShellScript "amp-runner" ''
    set -eu
    # Load user-owned configuration after dropping privileges.
    envfile=${home}/.config/amp-runner/env
    if [ ! -f "$envfile" ]; then
      echo "amp-runner: $envfile missing; place AMP_API_KEY=... (see README). Retrying." >&2
      exit 1
    fi
    set -a
    . "$envfile"
    set +a
    if [ -z "''${AMP_API_KEY:-}" ]; then
      echo "amp-runner: AMP_API_KEY unset in $envfile. Retrying." >&2
      exit 1
    fi
    exec ${amp}/bin/amp --no-tui --runner-id exedev --remote-control-terminal \
      --discover-dirs=${home} --discover-depth 3
  '';
in
{
  # Supply the account and tools; the agent owns its backed-up home contents.
  users.users.amp = {
    uid = 2002;
    group = "amp";
    inherit home;
    createHome = true;
    isSystemUser = true;
    shell = pkgs.bashInteractive;
    description = "Amp runner";
    packages = with pkgs; [
      amp
      chromium
      agent-browser
      himalaya
      sops
      age
      gh
      curl
      jq
      ripgrep
      coreutils
      findutils
      gnused
      python3
      openssl
      nodejs_22
      git
      jujutsu
      tmux
      fd
      ledger
    ];
  };
  users.groups.amp.gid = 2002;

  # User-owned ingress configuration remains reloadable without root.
  services.ingress.tenants.amp = {
    upstreamPort = 8084;
  };

  exedev.backup.paths = [ home ];

  systemd.services.amp-runner = {
    wantedBy = [ "multi-user.target" ];
    # Restore the user-owned configuration before starting the runner.
    wants = [ "backup-restore.service" ];
    after = [ "backup-restore.service" ];
    path = [ "/etc/profiles/per-user/amp" ];
    environment = toolEnvironment // {
      HOME = home;
      SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt";
    };
    serviceConfig = {
      User = "amp";
      WorkingDirectory = home;
      ExecStart = runner;
      Restart = "always";
      RestartSec = 30;
    };
    startLimitIntervalSec = 0;
  };
}
