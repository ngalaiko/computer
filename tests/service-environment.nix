{ pkgs }:
let
  probe = ''
    exec ${pkgs.python3}/bin/python -c 'import json, os; print(json.dumps({k: v for k, v in os.environ.items() if k.startswith(("RESTIC_", "B2_", "TEST_"))}))'
  '';
  config = (import ../modules/exedev { inherit pkgs; }).eval {
    nix.enable = false;
    services.backup.enable = true;
    s6.logDir = "$TMPDIR/service-logs";
    s6.services = {
      probe = {
        run = probe;
        finish = probe;
      };
      probe-once = {
        type = "oneshot";
        run = probe;
      };
      backup-cron.run = pkgs.lib.mkForce probe;
      backup-restore.run = pkgs.lib.mkForce probe;
    };
  };
in
pkgs.runCommand "service-environment-check"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.bash
    ];
  }
  ''
    root="$TMPDIR/root"
    mkdir -p "$root/run/s6/container_environment"
    chmod 755 "$root/run/s6/container_environment"
    ${config.image.activationFixups}
    test "$(stat -c %a "$root/run/s6/container_environment")" = 700
    python ${./test_service_environment.py} ${config.s6.build.serviceTree} ${config.s6.build.oneshots}
    touch "$out"
  ''
