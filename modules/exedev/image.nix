{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.exedev.image;
  toplevel = config.system.build.toplevel;

  # exe.dev's init exec's (rather than forks) an image Cmd whose basename is
  # `init`, so this runs as PID 1 and can hand over to systemd. Prepares what
  # NixOS stage 2 expects a container manager to provide, then boots the
  # current system profile, falling back to the baked generation.
  init = pkgs.writeScript "init" ''
    #!${pkgs.runtimeShell}
    set -u
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.util-linux
      ]
    }

    # stage 2 activates into /run before systemd starts; a tmpfs mounted later
    # would hide it.
    mountpoint -q /run || mount -t tmpfs -o mode=0755,nosuid,nodev,strictatime tmpfs /run
    [ -f /sys/fs/cgroup/cgroup.controllers ] || mount -t cgroup2 none /sys/fs/cgroup
    if mountpoint -q /proc/sys; then
      mount -o remount,rw /proc/sys
    fi

    # `exe.dev new --env` reaches only this process; keep the backup
    # credentials for restic in a root-only environment file.
    install -d -m 0700 /run/exedev
    (
      umask 077
      for name in ${lib.concatStringsSep " " cfg.passEnvironment}; do
        [ -n "''${!name+x}" ] || continue
        value=''${!name}
        printf "%s='%s'\n" "$name" "''${value//\'/\'\\\'\'}"
      done >${cfg.environmentFile}
    )

    sys=/nix/var/nix/profiles/system
    [ -x "$sys/init" ] || sys=${toplevel}
    exec "$sys/init"
  '';

  rootfs = pkgs.runCommand "exedev-rootfs" { } ''
    mkdir -p $out
    install -m 0755 ${init} $out/init
  '';

  workingDirOwner =
    let
      owners = lib.filterAttrs (_: u: u.home == cfg.workingDir) config.users.users;
      u = lib.head (lib.attrValues owners);
    in
    if owners == { } then "0:0" else "${toString u.uid}:${toString config.users.groups.${u.group}.gid}";

  image = pkgs.dockerTools.buildLayeredImageWithNixDb {
    inherit (cfg) name maxLayers;
    tag = "latest";
    created = "1970-01-01T00:00:01Z";
    contents = [ rootfs ];
    # Generation 1 is the baked system; nixos-rebuild adds the next ones.
    # /init is copied, not linked: exe.dev's OCI conversion drops some
    # top-level symlinks.
    extraCommands = ''
      rm init
      install -m 0755 ${init} init
      mkdir -p nix/var/nix/profiles tmp
      ln -s ${toplevel} nix/var/nix/profiles/system-1-link
      ln -s system-1-link nix/var/nix/profiles/system
    '';
    # exe.dev's init fails when WorkingDir is missing.
    fakeRootCommands = ''
      chmod 1777 tmp
      mkdir -p .${cfg.workingDir}
      chown ${workingDirOwner} .${cfg.workingDir}
    '';
    config = {
      Cmd = [ "/init" ];
      WorkingDir = cfg.workingDir;
      Labels = cfg.labels;
      ExposedPorts = lib.genAttrs (map (p: "${toString p}/tcp") cfg.exposedPorts.tcp) (_: { });
    };
  };
in
{
  options.exedev.image = {
    name = mkOption {
      type = types.str;
      description = "OCI image name.";
    };
    labels = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "OCI image labels.";
    };
    workingDir = mkOption {
      type = types.str;
      default = "/";
      description = "Container working directory; created in the image, owned by the user whose home it is.";
    };
    exposedPorts.tcp = mkOption {
      type = types.listOf types.port;
      default = [ ];
      description = "TCP ports to expose on the image.";
    };
    maxLayers = mkOption {
      type = types.int;
      default = 100;
      description = "Layer budget for buildLayeredImage.";
    };
    passEnvironment = mkOption {
      type = types.listOf (types.strMatching "[A-Za-z_][A-Za-z0-9_]*");
      default = [ ];
      description = "Variables from the exe.dev VM environment written to environmentFile at boot.";
    };
    environmentFile = mkOption {
      type = types.str;
      default = "/run/exedev/environment";
      readOnly = true;
      description = "Root-only file holding passEnvironment, in systemd EnvironmentFile format.";
    };
  };

  options.system.build.ociImage = mkOption {
    type = types.package;
    readOnly = true;
    description = "The OCI image exe.dev VMs are created from.";
  };

  config = {
    system.build.ociImage = image;

    boot.isContainer = true;

    # exe.dev's init owns DNS, /etc/hosts, /etc/hostname and the network.
    networking = {
      hostName = "";
      useDHCP = false;
      useHostResolvConf = false;
      resolvconf.enable = false;
      firewall.enable = false;
    };
    environment.etc.hosts.enable = false;

    # Provider-managed mounts and early-boot units, as in exe.dev's exeuntu.
    systemd.units =
      lib.genAttrs
        [
          "-.mount"
          "etc-hosts.mount"
          "etc-hostname.mount"
          "etc-resolv.conf.mount"
          "systemd-remount-fs.service"
        ]
        (_: {
          enable = lib.mkForce false;
        });
  };
}
