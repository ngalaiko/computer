#!@bash@/bin/bash
# In-place activation of a computer.exe "system generation". This is the
# switch-to-configuration analogue for our s6/OCI box: it makes the live rootfs
# and running services match a Nix-built generation WITHOUT recreating the VM.
#
# The generation ($gen) is self-locating — this script lives at <gen>/activate —
# and carries a stable ABI: rootfs/ manifest service/ oneshots/ reactivate fixups
# version. Everything here is driven off those, so no Nix eval happens at runtime.
#
# Modes:
#   switch  apply overlay+prune+fixups+s6-reload+reactivate, then flip the system
#           profile (numbered generation, rollback via `nix-env --rollback`).
#   boot    apply overlay+prune+fixups ONLY. Called by init-wrapper before svscan
#           is up; init replays the full oneshot set and starts svscan itself.
#   test    DRY RUN — report the overlay/prune/reload plan and mutate nothing.
#
# Safety invariants baked in here (see the plan / footgun review):
#   * overlay/prune are scoped to the manifest (managed files+symlinks only);
#     /var /home /root /etc/resolv.conf and friends are never in a manifest.
#   * fixups re-assert setuid /bin/sudo etc. every run — they are NOT in rootfs,
#     so skipping them would lock wheel out of root. Gated by a setuid check.
#   * tailscaled-computer (which serves our SSH) is restarted LAST and only if
#     changed; the deploy driver runs us detached and polls /run/activate.status.
#   * backup-restore is never in the switch reactivate set (it would clobber
#     live state with an old snapshot); boot runs it via init as usual.
set -u

# coreutils (most tools), gnugrep (grep), diffutils (cmp), util-linux (flock).
export PATH="@coreutils@/bin:@gnugrep@/bin:@diffutils@/bin:@utilLinux@/bin"
S6="@s6@"
NIX="@nix@/bin/nix-env"

gen=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
mode="${1:-switch}"
profile=/nix/var/nix/profiles/system
scan=/run/service
status=/run/activate.status

log() { printf '[activate:%s] %s\n' "$mode" "$*" >&2; }
die() {
  log "FATAL: $*"
  printf 'fail %s %s\n' "$gen" "$*" >"$status" 2>/dev/null || true
  exit 1
}

case "$mode" in
  switch | boot | test) ;;
  *) die "unknown mode: $mode (want switch|boot|test)" ;;
esac

# 0 if the live path $2 already matches the generation source $1 (so we can skip
# rewriting it — keeps switches quiet and avoids churning /bin/sh needlessly).
same_as_gen() {
  local src="$1" dst="$2"
  if [ -L "$src" ]; then
    [ -L "$dst" ] && [ "$(readlink "$src")" = "$(readlink "$dst")" ]
  else
    [ -f "$dst" ] && [ ! -L "$dst" ] && cmp -s "$src" "$dst"
  fi
}

# atomically install one managed path (symlink or regular file) via temp+rename.
overlay_one() {
  local rel="$1" src="$gen/rootfs/$1" dst="/$1" dir tmp
  dir=$(dirname "$dst")
  mkdir -p "$dir" || return 1
  tmp="$dir/.act.$$.$(basename "$dst")"
  if [ -L "$src" ]; then
    ln -sfn "$(readlink "$src")" "$tmp" || return 1
  else
    cp -f "$src" "$tmp" || return 1
    chmod u+w "$tmp" 2>/dev/null || true
  fi
  mv -f "$tmp" "$dst" || {
    rm -f "$tmp"
    return 1
  }
}

# top-level subdir names of a scan dir; the glob skips dotfiles (svscan's
# .s6-svscan) and non-dirs without an ls|grep pipeline.
list_dirs() {
  local p
  [ -d "$1" ] || return 0
  for p in "$1"/*; do [ -d "$p" ] && printf '%s\n' "${p##*/}"; done
}

# atomically install one file: temp + rename within the destination dir.
# ($1 src, $2 dst dir, $3 basename)
place() { cp -L "$1" "$2/.$3.tmp" && chmod u+w "$2/.$3.tmp" && mv -f "$2/.$3.tmp" "$2/$3"; }

# refresh a changed longrun's run/finish[/log] scripts, then restart it.
# tailscaled-computer is deferred (it serves SSH); caller restarts it last.
copy_svc_files() {
  local name="$1" d="$scan/$1" g="$gen/service/$1" f
  for f in run finish; do
    if [ -f "$g/$f" ]; then
      place "$g/$f" "$d" "$f"
    elif [ -f "$d/$f" ]; then
      rm -f "$d/$f"
    fi
  done
  [ -f "$g/log/run" ] && place "$g/log/run" "$d/log" run
  [ "$name" != tailscaled-computer ] && "$S6/s6-svc" -r "$d"
}

# ---- single-flight (real modes only) ------------------------------------
if [ "$mode" != test ]; then
  exec 9>/run/activate.lock || die "cannot open /run/activate.lock"
  flock -n 9 || die "another activation is in progress"
fi

# ---- 0. temp gc-root so the closure can't be collected mid-activation ----
if [ "$mode" != test ]; then
  mkdir -p /nix/var/nix/gcroots
  ln -sfn "$gen" /nix/var/nix/gcroots/activate
fi

old=""
[ -L "$profile" ] && old=$(readlink -f "$profile" 2>/dev/null || true)

# ---- 1. overlay managed paths (manifest-scoped, temp+rename) ------------
changed_paths=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  # same_as_gen already returns non-zero when the live path is absent.
  if same_as_gen "$gen/rootfs/$rel" "/$rel"; then continue; fi
  changed_paths=$((changed_paths + 1))
  if [ "$mode" = test ]; then
    log "overlay: /$rel"
  else
    overlay_one "$rel" || log "overlay FAILED: /$rel"
  fi
done <"$gen/manifest"

# ---- 2. prune paths this generation no longer manages -------------------
# manifests are already LC_ALL=C-sorted at build (activate.nix), so comm reads
# them directly — no re-sort, no temp files, and no process substitution (the box
# has no /dev/fd, so `<(...)` would not work here anyway).
if [ -n "$old" ] && [ -e "$old/manifest" ]; then
  LC_ALL=C comm -23 "$old/manifest" "$gen/manifest" | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    p="/$rel"
    if [ -L "$p" ] || { [ -f "$p" ] && [ ! -L "$p" ]; }; then
      if [ "$mode" = test ]; then log "prune: $p"; else rm -f "$p" || log "prune FAILED: $p"; fi
    fi
  done
fi

# ---- 3. fixups (setuid sudo, sudoers, ld.so, tmp perms) -----------------
if [ "$mode" = test ]; then
  log "fixups: would run $gen/fixups /"
else
  "$gen/fixups" / || die "fixups failed"
  [ -u /bin/sudo ] || die "post-fixup check: /bin/sudo is not setuid — aborting before profile flip"
fi

# boot stops here: init-wrapper replays oneshots and brings up svscan itself.
if [ "$mode" = boot ]; then
  log "boot overlay complete"
  exit 0
fi

# ---- 4. s6 live-reload (switch/test) ------------------------------------
added="" changed="" removed="" tailscaled_changed=""
for name in $(list_dirs "$gen/service"); do
  if [ ! -d "$scan/$name" ]; then
    added="$added $name"
    if [ "$mode" != test ]; then
      tmp="/run/.svc-add.$$-$name"
      rm -rf "$tmp"
      if cp -rL "$gen/service/$name" "$tmp" && chmod -R u+w "$tmp" && mv "$tmp" "$scan/$name"; then :; else
        log "add FAILED: $name"
        rm -rf "$tmp"
      fi
    fi
  elif ! cmp -s "$gen/service/$name/run" "$scan/$name/run"; then
    changed="$changed $name"
    [ "$name" = tailscaled-computer ] && tailscaled_changed=1
    [ "$mode" != test ] && copy_svc_files "$name"
  elif [ -f "$gen/service/$name/log/run" ] && ! cmp -s "$gen/service/$name/log/run" "$scan/$name/log/run"; then
    changed="$changed $name(log)"
    if [ "$mode" != test ]; then
      place "$gen/service/$name/log/run" "$scan/$name/log" run && "$S6/s6-svc" -r "$scan/$name/log"
    fi
  fi
done

for name in $(list_dirs "$scan"); do
  if [ ! -d "$gen/service/$name" ]; then
    removed="$removed $name"
    if [ "$mode" != test ]; then
      [ -d "$scan/$name/log" ] && "$S6/s6-svc" -d "$scan/$name/log"
      "$S6/s6-svc" -d "$scan/$name"
      "$S6/s6-svc" -wd -T 10000 "$scan/$name" 2>/dev/null || true
      rm -rf "$scan/${name:?}"
    fi
  fi
done

if [ "$mode" != test ]; then
  [ -n "$added$removed" ] && { "$S6/s6-svscanctl" -a "$scan" || log "svscanctl -a failed"; }
  if [ -n "$tailscaled_changed" ]; then
    log "restarting tailscaled-computer (serves SSH) — session may drop; driver polls $status"
    "$S6/s6-svc" -r "$scan/tailscaled-computer" || log "tailscaled restart failed"
  fi
fi
log "reload plan — added:${added:- none} changed:${changed:- none} removed:${removed:- none}"

# ---- 5. re-run reactivate-eligible oneshots (switch only), in NN order --
if [ -f "$gen/reactivate" ]; then
  for f in "$gen"/oneshots/*; do
    [ -e "$f" ] || continue
    base=${f##*/}
    name=${base#*-}
    if grep -qxF -- "$name" "$gen/reactivate"; then
      log "reactivate oneshot: $name"
      [ "$mode" != test ] && { "$f" || log "oneshot $name failed"; }
    fi
  done
fi

# ---- 6. commit ----------------------------------------------------------
if [ "$mode" = test ]; then
  log "DRY RUN complete — nothing applied ($changed_paths managed paths differ)"
  exit 0
fi

"$NIX" -p "$profile" --set "$gen" || die "profile flip failed"
rm -f /nix/var/nix/gcroots/activate
printf 'ok %s %s\n' "$gen" "$(date -u +%FT%TZ 2>/dev/null || echo now)" >"$status" || true
log "switched — profile -> $gen"
