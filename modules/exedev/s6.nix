# s6-overlay as PID 1: the overlay runtime, the s6-rc service graph generated
# from s6.services (cf. systemd.services), and the init wrapper the image boots.
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

  runFile =
    name: svc:
    pkgs.writeScript "s6-${name}-run" ''
      #!/command/with-contenv sh
      ${svc.run}
    '';
  upFile =
    name: svc:
    pkgs.writeScript "s6-${name}-up" ''
      #!/bin/sh
      ${svc.run}
    '';

  # The s6-rc source graph: <name>/{type,run|up,dependencies.d/*} plus
  # registration in the `user` bundle the overlay's base tarball defines.
  serviceGraph = pkgs.runCommand "s6-rc-services" { } (
    ''
      mkdir -p $out/etc/s6-overlay/s6-rc.d/user/contents.d
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (name: svc: ''
        d=$out/etc/s6-overlay/s6-rc.d/${name}
        mkdir -p $d/dependencies.d
        printf '%s' ${svc.type} > $d/type
        ${
          if svc.type == "longrun" then
            "cp ${runFile name svc} $d/run"
          else
            # a oneshot's up file holds a single execline command line
            ''printf '%s\n' "/command/with-contenv ${upFile name svc}" > $d/up''
        }
        ${lib.concatMapStrings (dep: ''
          touch $d/dependencies.d/${dep}
        '') svc.dependencies}
        touch $out/etc/s6-overlay/s6-rc.d/user/contents.d/${name}
      '') enabledServices
    )
  );

  longruns = lib.filterAttrs (_: s: s.type == "longrun") enabledServices;
  oneshots = lib.filterAttrs (_: s: s.type == "oneshot") enabledServices;

  # Oneshots in dependency order for the non-PID1 path (s6-rc does this itself
  # on the PID1 path).
  sortedOneshots =
    (lib.toposort (a: b: lib.elem a.name b.value.dependencies) (
      lib.mapAttrsToList (name: value: { inherit name value; }) oneshots
    )).result or (throw "s6: dependency cycle among oneshot services");

  # Scan directory for the non-PID1 path: longruns only, same run scripts.
  svscanDir = pkgs.runCommand "s6-svscan-services" { } (
    ''
      mkdir -p $out
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (name: svc: ''
        install -D ${runFile name svc} $out/${name}/run
      '') longruns
    )
  );

  # The image's Cmd. Two runtimes boot this image:
  #  - docker and plain OCI hosts run it as PID 1: mount the pseudo-filesystems
  #    the runtime didn't provide (must happen in the full-privilege PID-1
  #    context — a supervised mount did not fix sshd's PTY), then hand off to
  #    s6-overlay's /init.
  #  - exe.dev's exe-init keeps PID 1 for itself and runs this as a child with
  #    /proc and /dev/pts already mounted. s6-overlay refuses to run there
  #    ("can only run as pid 1"), so: publish the container env where
  #    with-contenv expects it, run the oneshots in dependency order, and
  #    supervise the longruns with s6-svscan, which is PID-agnostic.
  initWrapper = pkgs.writeScript "init-wrapper" ''
    #!/bin/sh
    set -u
    export PATH=/command:/bin:/sbin:/usr/bin

    if [ "$$" -eq 1 ]; then
      mkdir -p /proc /dev/pts
      ${pkgs.util-linux}/bin/mountpoint -q /proc || ${pkgs.util-linux}/bin/mount -t proc proc /proc || true
      ${pkgs.util-linux}/bin/mountpoint -q /dev/pts || ${pkgs.util-linux}/bin/mount -t devpts devpts /dev/pts -o gid=5,mode=620,ptmxmode=666 || true
      [ -e /dev/ptmx ] || ln -s pts/ptmx /dev/ptmx || true
      exec /init "$@"
    fi

    mkdir -p /run/s6
    /command/s6-dumpenv /run/s6/container_environment
    ${lib.concatMapStrings (s: ''
      ${upFile s.name s.value}
    '') sortedOneshots}
    mkdir -p /run/service
    cp -rL ${svscanDir}/. /run/service/
    chmod -R u+w /run/service
    exec /command/s6-svscan /run/service
  '';

  # /proc and /dev/pts pre-created: initWrapper's mkdir can't cover a read-only /dev.
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
              description = "Shell body: exec a long-running process (longrun) or perform setup (oneshot). Runs with the container env (with-contenv).";
            };
            dependencies = mkOption {
              type = types.listOf types.str;
              default = [ "base" ];
              description = "s6-rc services this one starts after.";
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
  };
}
