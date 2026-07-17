{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;

  # passwd shells and shebangs expect /bin/sh.
  binSh = pkgs.runCommand "bin-sh" { } ''
    mkdir -p $out/bin
    ln -s ${pkgs.bashInteractive}/bin/bash $out/bin/sh
  '';

  systemPath = pkgs.buildEnv {
    name = "system-path";
    paths = [ binSh ] ++ config.image.packages;
    pathsToLink = [
      "/bin"
      "/sbin"
      "/share"
    ];
  };

  etc = pkgs.runCommand "exedev-etc" { } (
    ''
      mkdir -p $out/etc
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (
        _: f:
        let
          src =
            if f.source != null then
              f.source
            else
              pkgs.writeText "etc-${lib.replaceStrings [ "/" ] [ "-" ] f.target}" f.text;
        in
        ''
          install -D -m${f.mode} ${src} "$out/etc/${f.target}"
        ''
      ) config.environment.etc
    )
  );

  # chmod -R u+w after each copy so the next tree can merge into store dirs.
  rootfs = pkgs.runCommand "exedev-rootfs" { } (
    ''
      mkdir -p $out
    ''
    + lib.concatMapStrings (d: ''
      cp -a ${d}/. $out/
      chmod -R u+w $out
    '') config.image.rootPaths
    + ''
      # /bin and /sbin must be real dirs, not symlinks: a top-level symlinked
      # dir survives docker but not exe.dev's OCI->rootfs conversion.
      for d in bin sbin; do
        mkdir -p $out/$d
        if [ -d ${systemPath}/$d ]; then
          cp -a ${systemPath}/$d/. $out/$d/
        fi
      done
      chmod -R u+w $out/bin $out/sbin
      # no login(1): the image has no PAM login stack, and its absence sends
      # tailscale ssh down its direct-exec path.
      rm -f $out/bin/login
      mkdir -p $out/usr/bin
      ln -sfn ${systemPath}/share $out/usr/share
      ln -sfn ${pkgs.coreutils}/bin/env $out/usr/bin/env
    ''
  );

  image = pkgs.dockerTools.buildLayeredImage {
    name = config.image.name;
    tag = "latest";
    created = "1970-01-01T00:00:01Z";
    contents = [ rootfs ];
    maxLayers = config.image.maxLayers;
    # store paths can't hold these modes; fakeroot writes them into the layer
    fakeRootCommands = ''
      mkdir -p ./tmp ./var/tmp ./root
      chmod 1777 ./tmp ./var/tmp
      chmod 0755 ./root
    ''
    + config.image.fakeRootCommands;
    config = {
      Cmd = config.image.cmd;
      User = "0:0";
      Env = config.image.env;
      WorkingDir = config.image.workingDir;
      Labels = config.image.labels;
      ExposedPorts = lib.genAttrs (
        map (p: "${toString p}/tcp") config.image.exposedPorts.tcp
        ++ map (p: "${toString p}/udp") config.image.exposedPorts.udp
      ) (_: { });
    };
  };
in
{
  options = {
    environment.etc = mkOption {
      description = "Files placed under /etc in the image (cf. NixOS environment.etc).";
      default = { };
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              text = mkOption {
                type = types.nullOr types.lines;
                default = null;
                description = "File contents. Mutually exclusive with source.";
              };
              source = mkOption {
                type = types.nullOr types.path;
                default = null;
                description = "Path to copy verbatim. Mutually exclusive with text.";
              };
              target = mkOption {
                type = types.str;
                default = name;
                description = "Path under /etc (defaults to the attribute name).";
              };
              mode = mkOption {
                type = types.str;
                default = "0644";
                description = "Octal file mode.";
              };
            };
          }
        )
      );
    };

    image = {
      name = mkOption {
        type = types.str;
        description = "OCI image name.";
      };
      labels = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "OCI image labels.";
      };
      packages = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Packages merged into /bin, /sbin, /usr/share.";
      };
      rootPaths = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Store paths overlaid onto the image root /.";
      };
      env = mkOption {
        type = types.listOf types.str;
        default = [
          "PATH=/command:/bin:/sbin:/usr/bin"
          "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
          "GIT_SSL_CAINFO=/etc/ssl/certs/ca-bundle.crt"
          "USER=root"
          "HOME=/root"
        ];
        description = "Container environment.";
      };
      fakeRootCommands = mkOption {
        type = types.lines;
        default = "";
        description = "Commands run under fakeroot over the image root (relative ./… paths) to bake ownership/modes.";
      };
      cmd = mkOption {
        type = types.listOf types.str;
        description = "Image Cmd.";
      };
      workingDir = mkOption {
        type = types.str;
        default = "/";
        description = "Container working directory.";
      };
      maxLayers = mkOption {
        type = types.int;
        default = 100;
        description = "Layer budget for buildLayeredImage.";
      };
      exposedPorts = {
        tcp = mkOption {
          type = types.listOf types.port;
          default = [ ];
          description = "TCP ports to expose on the image.";
        };
        udp = mkOption {
          type = types.listOf types.port;
          default = [ ];
          description = "UDP ports to expose on the image.";
        };
      };
    };

    build = {
      rootfs = mkOption {
        type = types.package;
        readOnly = true;
        description = "The merged root filesystem tree.";
      };
      image = mkOption {
        type = types.package;
        readOnly = true;
        description = "The OCI image.";
      };
    };
  };

  config = {
    build = { inherit rootfs image; };

    image.rootPaths = [ etc ];

    environment.etc = {
      "nsswitch.conf".text = ''
        passwd: files
        group: files
        shadow: files
        hosts: files dns
        networks: files dns
        protocols: files
        services: files
        ethers: files
        rpc: files
      '';
      "ssl/certs/ca-bundle.crt".source = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      "ssl/certs/ca-certificates.crt".source = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      protocols.source = "${pkgs.iana-etc}/etc/protocols";
      services.source = "${pkgs.iana-etc}/etc/services";
      # sshd resets PATH; login shells restore it and source /etc/profile.d.
      profile.text = ''
        export PATH=/command:/bin:/sbin:/usr/bin
        export SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
        export GIT_SSL_CAINFO=/etc/ssl/certs/ca-bundle.crt
        for f in /etc/profile.d/*.sh; do
          [ -r "$f" ] && . "$f"
        done
      '';
    };
  };
}
