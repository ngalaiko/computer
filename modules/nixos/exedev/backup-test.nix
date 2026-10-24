{
  pkgs,
  script,
  sourceRestic,
}:
let
  restore = pkgs.writeShellScript "backup-restore-test" (
    "set -euo pipefail\n"
    +
      builtins.replaceStrings
        [ sourceRestic "/var/lib/backup-restore/done" "--target /" ]
        [ "${pkgs.restic}/bin/restic" "$TEST_ROOT/done" "--target \"$TEST_ROOT/restore\"" ]
        (builtins.unsafeDiscardStringContext script)
  );
in
pkgs.runCommand "backup-restore-test" { nativeBuildInputs = [ pkgs.restic ]; } ''
  export TEST_ROOT="$TMPDIR/test"
  mkdir -p "$TEST_ROOT"
  export RESTIC_REPOSITORY="$TEST_ROOT/repo"
  export RESTIC_PASSWORD=correct
  export RESTIC_CACHE_DIR="$TEST_ROOT/cache"
  restic init

  mkdir -p "$TEST_ROOT/source"
  echo preserved > "$TEST_ROOT/source/note"
  restic backup --host exedev --tag auto "$TEST_ROOT/source"

  export RESTIC_PASSWORD=wrong
  if ${restore}; then
    echo "restore accepted invalid credentials" >&2
    exit 1
  fi
  test ! -e "$TEST_ROOT/done"

  export RESTIC_PASSWORD=correct
  ${restore}
  test -e "$TEST_ROOT/done"
  cmp "$TEST_ROOT/source/note" "$TEST_ROOT/restore/$TEST_ROOT/source/note"

  rm "$TEST_ROOT/done"
  export RESTIC_REPOSITORY="$TEST_ROOT/empty"
  restic init
  ${restore}
  test -e "$TEST_ROOT/done"

  rm "$TEST_ROOT/done"
  export RESTIC_REPOSITORY="$TEST_ROOT/missing"
  if ${restore}; then
    echo "restore accepted an inaccessible repository" >&2
    exit 1
  fi
  test ! -e "$TEST_ROOT/done"
  touch $out
''
