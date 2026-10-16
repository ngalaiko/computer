# restic -> B2, credentials from the exe.dev VM environment. Backups and
# retention run on separate timers; the latest snapshot is restored on boot.
{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.exedev.backup;
  envFile = config.exedev.image.environmentFile;

  # Every restic op is scoped to this host. Without it, a repo shared with
  # another machine restores whichever box wrote the newest snapshot, and
  # forget --prune applies retention across both boxes.
  scope = [
    "--host"
    cfg.host
    "--tag"
    "auto"
  ];

  common = {
    environmentFile = envFile;
    initialize = true;
  };

  restic = "${pkgs.restic}/bin/restic";
in
{
  options.exedev.backup = {
    host = mkOption {
      type = types.str;
      default = "exedev";
      description = ''
        restic --host for this machine's snapshots; backup, forget and
        restore-on-boot are confined to it. Must be unique per machine sharing
        a repo. Fixed rather than the OS hostname because exe.dev boxes share
        hostnames.
      '';
    };
    paths = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Absolute paths to back up; restored to the same locations on boot.";
    };
  };

  config = {
    exedev.image.passEnvironment = [
      "RESTIC_REPOSITORY"
      "RESTIC_PASSWORD"
      "B2_ACCOUNT_ID"
      "B2_ACCOUNT_KEY"
    ];

    services.restic.backups = {
      b2 = common // {
        inherit (cfg) paths;
        extraBackupArgs = scope;
        exclude = [
          "__pycache__"
          ".venv"
          "venv"
          "node_modules"
          # pi plugins installed at runtime (`pi install npm:…`) are not
          # regeneratable; last match wins, so this re-includes them.
          "!**/.pi/**/node_modules"
          ".cache"
          "checkpoints"
          "backups"
        ];
        timerConfig.OnCalendar = "*:0/15";
      };
      # --prune repacks pack files (B2 API calls + egress); run it daily, not
      # per backup.
      b2-prune = common // {
        pruneOpts = scope ++ [
          "--keep-last 24"
          "--keep-hourly 24"
          "--keep-daily 14"
        ];
        timerConfig.OnCalendar = "03:17";
      };
    };

    systemd.services = {
      restic-backups-b2.unitConfig.ConditionFileNotEmpty = envFile;
      restic-backups-b2-prune.unitConfig.ConditionFileNotEmpty = envFile;

      # Runs as root, so restic restores the snapshot's numeric owners. Order
      # services that need restored state after this unit.
      backup-restore = {
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        unitConfig.ConditionFileNotEmpty = envFile;
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          EnvironmentFile = envFile;
          CacheDirectory = "restic-backups-b2";
          TimeoutStartSec = 300;
        };
        environment.RESTIC_CACHE_DIR = "/var/cache/restic-backups-b2";
        script = ''
          if ! ${restic} cat config >/dev/null 2>&1; then
            echo "restore: repo has no snapshots yet" >&2
            exit 0
          fi
          if ${restic} snapshots ${lib.escapeShellArgs scope} --latest 1 >/dev/null 2>&1; then
            ${restic} restore latest ${lib.escapeShellArgs scope} --target / \
              || echo "restore: failed; continuing with on-disk state" >&2
          else
            echo "restore: no snapshots for host ${cfg.host} yet" >&2
          fi
        '';
      };
    };
  };
}
