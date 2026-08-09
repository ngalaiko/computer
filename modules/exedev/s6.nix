{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.s6;

  enabledServices = lib.filterAttrs (_: s: s.enable) cfg.services;
  longruns = lib.filterAttrs (_: s: s.type == "longrun") enabledServices;
  oneshots = lib.filterAttrs (_: s: s.type == "oneshot") enabledServices;

  # longrun stdout+stderr flow to its logger.
  runFile =
    name: svc:
    pkgs.writeScript "s6-${name}-run" ''
      #!/command/with-contenv sh
      exec 2>&1
      ${svc.run}
    '';
  # oneshots have no logger pipe; self-redirect to the same log path.
  upFile =
    name: svc:
    pkgs.writeScript "s6-${name}-up" ''
      #!/bin/sh
      mkdir -p ${cfg.logDir}/${name}
      exec >>${cfg.logDir}/${name}/current 2>&1
      ${svc.run}
    '';
  downFile =
    name: svc:
    pkgs.writeScript "s6-${name}-down" ''
      #!/bin/sh
      mkdir -p ${cfg.logDir}/${name}
      exec >>${cfg.logDir}/${name}/current 2>&1
      ${svc.down}
    '';
  logFile =
    name:
    pkgs.writeScript "s6-${name}-log" ''
      #!/bin/sh
      mkdir -p ${cfg.logDir}/${name}
      exec ${cfg.package}/command/s6-log -b T n${toString cfg.logKeep} s${toString cfg.logSize} ${cfg.logDir}/${name}
    '';

  finishFile =
    name: svc:
    pkgs.writeScript "s6-${name}-finish" ''
      #!/bin/sh
      exec >>${cfg.logDir}/${name}/current 2>&1
      ${svc.finish}
    '';

  deps = svc: lib.concatMapStrings (d: "touch $dir/dependencies.d/${d}\n") svc.dependencies;

  serviceGraph = pkgs.runCommand "s6-rc-services" { } (
    ''
      mkdir -p $out/etc/s6-overlay/s6-rc.d/user/contents.d
      root=$out/etc/s6-overlay/s6-rc.d
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (
        name: svc:
        if svc.type == "longrun" then
          ''
            dir=$root/${name}
            mkdir -p $dir/dependencies.d
            printf longrun > $dir/type
            cp ${runFile name svc} $dir/run
            ${lib.optionalString (svc.finish != "") "cp ${finishFile name svc} $dir/finish"}
            printf '%s' ${name}-log > $dir/producer-for
            ${deps svc}
            l=$root/${name}-log
            mkdir -p $l
            printf longrun > $l/type
            cp ${logFile name} $l/run
            printf '%s' ${name} > $l/consumer-for
            printf '%s' ${name}-pipeline > $l/pipeline-name
            touch $root/user/contents.d/${name}-pipeline
          ''
        else
          ''
            dir=$root/${name}
            mkdir -p $dir/dependencies.d
            printf oneshot > $dir/type
            printf '%s\n' "/command/with-contenv ${upFile name svc}" > $dir/up
            ${lib.optionalString (
              svc.down != ""
            ) ''printf '%s\n' "/command/with-contenv ${downFile name svc}" > $dir/down''}
            ${deps svc}
            touch $root/user/contents.d/${name}
          ''
      ) enabledServices
    )
  );

  # dependency order for the non-PID1 path (s6-rc handles it on the PID1 path).
  sortedOneshots =
    (lib.toposort (a: b: lib.elem a.name b.value.dependencies) (
      lib.mapAttrsToList (name: value: { inherit name value; }) oneshots
    )).result or (throw "s6: dependency cycle among oneshot services");

  # bare s6-svscan logs a service when its dir holds a log/ subdir.
  svscanDir = pkgs.runCommand "s6-svscan-services" { } (
    ''
      mkdir -p $out
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (name: svc: ''
        install -D ${runFile name svc} $out/${name}/run
        ${lib.optionalString (svc.finish != "") "install -D ${finishFile name svc} $out/${name}/finish"}
        install -D ${logFile name} $out/${name}/log/run
      '') longruns
    )
  );

  # The generation ABI (consumed by build.system's activate and by the boot
  # handoff below): oneshots as NN-<name> up-scripts in toposort order, so
  # `$gen/oneshots/*` globs replay them without a Nix eval. Same upFile the
  # inline boot path runs, so boot and activate stay identical.
  oneshotsDir = pkgs.runCommand "s6-oneshots" { } (
    ''
      mkdir -p $out
    ''
    + lib.concatStrings (
      lib.imap0 (
        i: s: "cp ${upFile s.name s.value} $out/${lib.fixedWidthString 3 "0" (toString i)}-${s.name}\n"
      ) sortedOneshots
    )
  );

  # oneshots safe to replay on a live `activate switch` (default-deny; see the
  # per-service `reactivate` flag). Boot replays the FULL set regardless.
  reactivateNames = lib.attrNames (lib.filterAttrs (_: s: s.reactivate) oneshots);

  # Dual boot path. As PID 1 (docker): mount the pseudo-filesystems (must be
  # PID 1 — a supervised mount didn't fix ssh PTYs) then exec s6-overlay's
  # /init. As a child (exe.dev's exe-init keeps PID 1): s6-overlay refuses to
  # run, so dump the container env, run oneshots in order, and supervise
  # longruns with s6-svscan (PID-agnostic).
  initWrapper = pkgs.writeScript "init-wrapper" ''
    #!/bin/sh
    set -u
    export PATH=/command:/bin:/sbin:/usr/bin

    if [ "$$" -eq 1 ]; then
      mkdir -p /proc /dev/pts
      ${pkgs.util-linux}/bin/mountpoint -q /proc || ${pkgs.util-linux}/bin/mount -t proc proc /proc || true
      ${pkgs.util-linux}/bin/mountpoint -q /dev/pts || ${pkgs.util-linux}/bin/mount -t devpts devpts /dev/pts -o gid=5,mode=620,ptmxmode=666 || true
      [ -e /dev/ptmx ] || ln -s pts/ptmx /dev/ptmx || true
      [ -e /dev/fd ] || ln -sfn /proc/self/fd /dev/fd || true
      exec /init "$@"
    fi

    mkdir -p /run/s6
    /command/s6-dumpenv /run/s6/container_environment

    # exe.dev's minimal /dev omits /dev/fd etc.; provide the conventional symlinks
    # so bash process substitution (and tools that open /dev/fd/N) work — e.g.
    # building derivations on the box, and the activate prune path.
    if [ -e /proc/self/fd ]; then
      ln -sfn /proc/self/fd /dev/fd 2>/dev/null || true
      ln -sfn /proc/self/fd/0 /dev/stdin 2>/dev/null || true
      ln -sfn /proc/self/fd/1 /dev/stdout 2>/dev/null || true
      ln -sfn /proc/self/fd/2 /dev/stderr 2>/dev/null || true
    fi

    # Boot handoff: exe.dev `restart` reboots the BASE image, but if an in-place
    # deploy has set the system profile, come up on THAT generation instead of
    # the baked base — overlay its rootfs/fixups, replay its (full) oneshot set,
    # and svscan its services. First-ever boot (no profile yet) falls back to the
    # baked base. This makes gen/{activate,oneshots,service} the ABI.
    sys=/nix/var/nix/profiles/system
    if [ -e "$sys" ]; then
      gen=$(readlink -f "$sys")
      "$gen/activate" boot || echo "boot: activate failed; continuing on generation" >&2
      oneshots="$gen/oneshots"
      svc="$gen/service"
    else
      # first-ever boot: replay the base's own copy of the same toposorted set.
      oneshots=${oneshotsDir}
      svc=${svscanDir}
    fi
    for f in "$oneshots"/*; do [ -e "$f" ] && "$f"; done
    mkdir -p /run/service
    cp -rL "$svc"/. /run/service/
    chmod -R u+w /run/service
    exec /command/s6-svscan /run/service
  '';

  # pre-created: initWrapper's mkdir can't cover a read-only /dev.
  bootTree = pkgs.runCommand "s6-boot" { } ''
    mkdir -p $out/proc $out/dev/pts
    cp ${initWrapper} $out/init-wrapper
  '';
in
{
  options.s6 = {
    package = mkOption {
      type = types.package;
      default = import ../../packages/s6-overlay { inherit pkgs; };
      defaultText = lib.literalExpression "the s6-overlay packaged in packages/s6-overlay";
      description = "Unpacked s6-overlay tree (/init, /command, /package).";
    };

    logDir = mkOption {
      type = types.str;
      default = "/var/log";
      description = "Per-service logs written to <logDir>/<service>/current.";
    };
    logKeep = mkOption {
      type = types.int;
      default = 10;
      description = "Rotated log files to retain per service.";
    };
    logSize = mkOption {
      type = types.int;
      default = 1000000;
      description = "Rotate a service log at this size (bytes).";
    };

    build = {
      serviceTree = mkOption {
        type = types.package;
        readOnly = true;
        description = "The svscan longrun tree (/run/service source); build.system ships it as gen/service for the reload diff.";
      };
      oneshots = mkOption {
        type = types.package;
        readOnly = true;
        description = "Toposorted NN-<name> oneshot up-scripts; build.system ships them as gen/oneshots for boot replay + switch re-run.";
      };
      reactivate = mkOption {
        type = types.listOf types.str;
        readOnly = true;
        description = "Oneshot names safe to re-run on `activate switch` (the reactivate=true set).";
      };
    };

    services = mkOption {
      description = "s6-rc services, registered in the user bundle.";
      default = { };
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Whether to include this service in the graph.";
            };
            type = mkOption {
              type = types.enum [
                "longrun"
                "oneshot"
              ];
              default = "longrun";
              description = "s6-rc service type.";
            };
            run = mkOption {
              type = types.lines;
              description = "Shell body, run with the container env (with-contenv).";
            };
            down = mkOption {
              type = types.lines;
              default = "";
              description = "Oneshot shutdown body; only runs on the PID1 path (exe.dev's exe-init gives no orderly shutdown).";
            };
            finish = mkOption {
              type = types.lines;
              default = "";
              description = "Longrun finish body, run after each death of the run process with s6's exit-code args.";
            };
            dependencies = mkOption {
              type = types.listOf types.str;
              default = [ "base" ];
              description = "s6-rc services this one starts after.";
            };
            reactivate = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Oneshot only: re-run this oneshot during an in-place `activate
                switch` (not just at boot). Default-deny — only set it on
                idempotent seeders that are safe to replay against a live system
                (e.g. ingress route seeding). MUST stay false for anything that
                mutates state on run (e.g. backup-restore, which would restore an
                old snapshot over live data). Ignored for longruns (they reload
                via the svscan diff).
              '';
            };
          };
        }
      );
    };
  };

  config = {
    image.cmd = lib.mkDefault [ "/init-wrapper" ];
    image.rootPaths = [
      cfg.package
      serviceGraph
      bootTree
    ];
    # devpts is mounted with gid=5 (see initWrapper).
    users.groups.tty.gid = 5;

    s6.build = {
      serviceTree = svscanDir;
      oneshots = oneshotsDir;
      reactivate = reactivateNames;
    };
  };
}
