{
  pkgs,
  inputs,
  ...
}:
let
  home = "/var/lib/amp";
  assistantTools = inputs.assistant.devShells.${pkgs.stdenv.hostPlatform.system}.default;
  assistantPkgs = inputs.assistant.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  # These are tool requirements, not private account or data-path configuration.
  toolEnvironment = {
    inherit (assistantTools) AGENT_BROWSER_EXECUTABLE_PATH;
    FONTCONFIG_FILE = toString (
      assistantPkgs.makeFontsConf {
        fontDirectories = [ assistantPkgs.dejavu_fonts ];
      }
    );
  };
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
    cd ${home}
    exec ${amp}/bin/amp --no-tui --runner-id computer --remote-control-terminal \
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
    shell = "/bin/sh";
    description = "Amp runner";
    environment = toolEnvironment;
    packages =
      assistantTools.nativeBuildInputs
      ++ (with pkgs; [
        amp
        assistantPkgs.chromium
        python3
        openssl
        nodejs_22
        git
        jujutsu
        tmux
        fd
        ledger
      ]);
  };
  users.groups.amp.gid = 2002;

  # User-owned ingress configuration remains reloadable without root.
  services.ingress.tenants.amp = {
    upstreamPort = 8084;
  };

  services.backup.paths = [ home ];

  s6.services.amp-runner = {
    dependencies = [
      "base"
      # Restore the user-owned configuration before starting the runner.
      "backup-restore"
    ];
    run = ''
      exec ${pkgs.s6}/bin/s6-setuidgid amp \
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
