{ config, pkgs, ... }:
let
  home = "/home/dasha";
  runner = config.systemd.services.amp-runner;
in
{
  users.users.dasha = {
    uid = 2003;
    group = "dasha";
    isNormalUser = true;
    inherit home;
    homeMode = "0700";
    shell = pkgs.bashInteractive;
    description = "Dasha";
    # Same Ledger, browser, Git, Python, Node, and agent tools as the amp user.
    packages = config.users.users.amp.packages ++ [ pkgs.obsidian-headless ];
  };
  users.groups.dasha.gid = 2003;

  services.ingress.tenants.dasha.upstreamPort = 8086;

  exedev.backup.paths = [ home ];

  # Share only the ledger, without granting traversal into amp's private home.
  systemd.services.dasha-ledger = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "backup-restore.service" ];
    after = [ "backup-restore.service" ];
    unitConfig.ConditionPathIsDirectory = "/var/lib/amp/src/finance";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [
      pkgs.acl
      pkgs.findutils
      pkgs.util-linux
    ];
    script = ''
      setfacl -R -m u:2003:r-X /var/lib/amp/src/finance
      find /var/lib/amp/src/finance -type d -exec setfacl -m d:u:2003:r-x {} +
      mkdir -p ${home}/finance
      if ! mountpoint -q ${home}/finance; then
        mount -o bind,ro /var/lib/amp/src/finance ${home}/finance
      else
        mount -o remount,bind,ro ${home}/finance
      fi
    '';
  };

  systemd.services.dasha-amp-runner = {
    wantedBy = [ "multi-user.target" ];
    wants = [
      "backup-restore.service"
      "dasha-ledger.service"
    ];
    after = [
      "backup-restore.service"
      "dasha-ledger.service"
    ];
    path = [
      "/run/wrappers"
      "/etc/profiles/per-user/dasha"
      "/run/current-system/sw"
    ];
    environment = removeAttrs runner.environment [ "PATH" ] // {
      HOME = home;
      XDG_RUNTIME_DIR = "/run/user/${toString config.users.users.dasha.uid}";
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/${toString config.users.users.dasha.uid}/bus";
    };
    serviceConfig = {
      User = "dasha";
      WorkingDirectory = home;
      # The shared launcher reads credentials and discovers repos in $HOME.
      inherit (runner.serviceConfig) ExecStart;
      Restart = "always";
      RestartSec = 30;
    };
    startLimitIntervalSec = 0;
  };

  # nikita already has full wheel sudo. amp may manage Dasha, not root.
  security.sudo.extraRules = [
    {
      users = [ "amp" ];
      runAs = "dasha";
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
    {
      users = [ "amp" ];
      runAs = "root";
      commands =
        map
          (action: {
            command = "/run/current-system/sw/bin/systemctl ${action} dasha-amp-runner.service";
            options = [ "NOPASSWD" ];
          })
          [
            "start"
            "stop"
            "restart"
          ];
    }
  ];
}
