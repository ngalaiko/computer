{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.services.sshd;
  keysUser = config.users.users.${cfg.authorizedKeys.user};
  keysGid = toString config.users.groups.${keysUser.group}.gid;
in
{
  options.services.sshd = {
    enable = lib.mkEnableOption "the OpenSSH server, supervised by s6";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.openssh;
      defaultText = lib.literalExpression "pkgs.openssh";
      description = "OpenSSH package.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 22;
      description = "Port sshd listens on.";
    };
    authorizedKeys = {
      user = lib.mkOption {
        type = lib.types.str;
        description = "Login account whose authorized_keys the env var populates; declare it in users.users.";
      };
      env = lib.mkOption {
        type = lib.types.str;
        default = "EXE_DEV_AUTHORIZED_KEYS";
        description = "Environment variable exe.dev injects the public keys through.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.sshd = {
      uid = 30033;
      group = "sshd";
      description = "sshd privilege separation user";
    };
    users.groups.sshd.gid = 30033;

    environment.etc."ssh/sshd_config".text = ''
      Port ${toString cfg.port}
      HostKey /etc/ssh/ssh_host_ed25519_key
      HostKey /etc/ssh/ssh_host_rsa_key
      PidFile /run/sshd.pid
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin no
      PubkeyAuthentication yes
      UsePAM no
      X11Forwarding no
      AllowTcpForwarding yes
      PermitTTY yes
      PrintMotd no
      Subsystem sftp internal-sftp
    '';

    s6.services.sshd-keygen = {
      type = "oneshot";
      run = ''
        set -eu
        mkdir -p /run/sshd /etc/ssh
        [ -f /etc/ssh/ssh_host_ed25519_key ] || ${cfg.package}/bin/ssh-keygen -q -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
        [ -f /etc/ssh/ssh_host_rsa_key ]     || ${cfg.package}/bin/ssh-keygen -q -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
      '';
    };

    # keys arrive via env only at boot, so this is a runtime step; must win
    # over a restored authorized_keys, so it runs after backup-restore.
    s6.services.authorized-keys = {
      type = "oneshot";
      dependencies = [
        "base"
      ]
      ++ lib.optional config.services.backup.enable "backup-restore";
      run = ''
        set -eu
        mkdir -p ${keysUser.home}/.ssh
        chmod 0700 ${keysUser.home}/.ssh
        if [ -n "''${${cfg.authorizedKeys.env}:-}" ]; then
          printf '%s\n' "''$${cfg.authorizedKeys.env}" > ${keysUser.home}/.ssh/authorized_keys
          chmod 0600 ${keysUser.home}/.ssh/authorized_keys
        fi
        chown ${toString keysUser.uid}:${keysGid} ${keysUser.home}
        chown -R ${toString keysUser.uid}:${keysGid} ${keysUser.home}/.ssh
      '';
    };

    s6.services.sshd = {
      dependencies = [
        "base"
        "sshd-keygen"
      ];
      # sshd refuses to start unless invoked by absolute path.
      run = ''
        exec "$(command -v sshd)" -D -e -f /etc/ssh/sshd_config
      '';
    };

    image.packages = [ cfg.package ];
    image.exposedPorts.tcp = [ cfg.port ];
  };
}
