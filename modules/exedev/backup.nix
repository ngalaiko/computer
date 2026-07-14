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
    ${restic} backup --tag auto ${excludeArgs} ${quotedPaths}
    ${restic} forget --tag auto --keep-last ${toString cfg.keepLast} --prune
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
    keepLast = mkOption {
      type = types.int;
      default = 24;
      description = "Recent snapshots to retain; older ones are pruned.";
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
