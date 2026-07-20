{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.services.backup;
  restic = "${pkgs.restic}/bin/restic";
  quotedPaths = lib.concatMapStringsSep " " lib.escapeShellArg cfg.paths;
  excludeArgs = lib.concatMapStringsSep " " (p: "--exclude=${lib.escapeShellArg p}") cfg.exclude;

  # retention flags for `restic forget`; a null keep-* is omitted.
  keepArgs = lib.concatStringsSep " " (
    lib.optional (cfg.keepLast != null) "--keep-last ${toString cfg.keepLast}"
    ++ lib.optional (cfg.keepHourly != null) "--keep-hourly ${toString cfg.keepHourly}"
    ++ lib.optional (cfg.keepDaily != null) "--keep-daily ${toString cfg.keepDaily}"
    ++ lib.optional (cfg.keepWeekly != null) "--keep-weekly ${toString cfg.keepWeekly}"
    ++ lib.optional (cfg.keepMonthly != null) "--keep-monthly ${toString cfg.keepMonthly}"
  );

  # no repo configured -> no-op (so the image runs without B2).
  guard = ''
    if [ -z "''${RESTIC_REPOSITORY:-}" ]; then
      echo "backup: RESTIC_REPOSITORY unset — skipping." >&2
      exit 0
    fi
    export RESTIC_CACHE_DIR="''${RESTIC_CACHE_DIR:-/var/cache/restic}"
  '';

  backupScript = pkgs.writeShellScript "b2-backup" ''
    set -u
    ${guard}
    ${restic} cat config >/dev/null 2>&1 || ${restic} init
    # hard VM stops strand locks; drop the stale ones before backing up.
    ${restic} unlock
    ${restic} backup --tag auto ${excludeArgs} ${quotedPaths}
  '';

  # retention runs on its own, infrequent schedule: --prune repacks pack files
  # (B2 API calls + egress), so running it per-backup is wasteful. Decoupled
  # here so snapshots span days rather than the ~6h a 15-min keep-last-24 kept.
  forgetScript = pkgs.writeShellScript "b2-forget" ''
    set -u
    ${guard}
    if ! ${restic} cat config >/dev/null 2>&1; then
      echo "forget: repo not initialized yet — skipping." >&2
      exit 0
    fi
    # prune's lock is exclusive; drop locks stranded by hard stops first.
    ${restic} unlock
    ${restic} forget --tag auto ${keepArgs} --prune \
      || echo "backup: forget/prune failed — retention not applied." >&2
  '';

  # runs as root, so restic restores the snapshot's numeric owners.
  restoreScript = pkgs.writeShellScript "b2-restore" ''
    set -u
    ${guard}
    if ! ${restic} cat config >/dev/null 2>&1; then
      echo "restore: repo has no snapshots yet — nothing to restore." >&2
      exit 0
    fi
    if ${restic} snapshots --tag auto --latest 1 >/dev/null 2>&1; then
      echo "restore: restoring latest snapshot" >&2
      ${restic} restore latest --tag auto --target / \
        || echo "restore: failed — continuing with current on-disk state." >&2
    else
      echo "restore: no snapshots yet" >&2
    fi
  '';

  crontab = pkgs.writeText "b2-crontab" ''
    ${cfg.schedule} ${backupScript}
    ${cfg.pruneSchedule} ${forgetScript}
  '';
in
{
  options.services.backup = {
    enable = lib.mkEnableOption "periodic restic->B2 backup of services.backup.paths with restore-on-start";
    paths = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Absolute paths to back up; restored to the same locations on boot.";
    };
    exclude = mkOption {
      type = types.listOf types.str;
      default = [
        "__pycache__"
        ".venv"
        "venv"
        "node_modules"
        ".cache"
        "checkpoints"
        "backups"
      ];
      description = "restic exclude patterns (regeneratable dirs).";
    };
    schedule = mkOption {
      type = types.str;
      default = "*/15 * * * *";
      description = "Backup cron schedule (supercronic 5-field format).";
    };
    pruneSchedule = mkOption {
      type = types.str;
      default = "17 3 * * *";
      description = "forget+prune (retention) cron schedule; runs far less often than backups because prune is expensive.";
    };
    keepLast = mkOption {
      type = types.nullOr types.int;
      default = 24;
      description = "restic forget --keep-last (null to omit).";
    };
    keepHourly = mkOption {
      type = types.nullOr types.int;
      default = 24;
      description = "restic forget --keep-hourly (null to omit).";
    };
    keepDaily = mkOption {
      type = types.nullOr types.int;
      default = 14;
      description = "restic forget --keep-daily (null to omit).";
    };
    keepWeekly = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "restic forget --keep-weekly (null to omit).";
    };
    keepMonthly = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "restic forget --keep-monthly (null to omit).";
    };
  };

  config = lib.mkIf cfg.enable {
    image.packages = [
      pkgs.restic
      pkgs.supercronic
    ];

    s6.services.backup-restore = {
      type = "oneshot";
      run = ''
        mkdir -p /var/cache/restic
        timeout 300 ${restoreScript} || echo "restore: timed out — continuing." >&2
      '';
    };

    s6.services.backup-cron.run = ''
      mkdir -p /var/cache/restic
      exec ${pkgs.supercronic}/bin/supercronic ${crontab}
    '';
  };
}
