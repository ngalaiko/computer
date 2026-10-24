{ pkgs, ... }:
let
  home = "/home/nikita";
  finance = "${home}/finance";
  finance-permissions = pkgs.writeShellScriptBin "finance-permissions" ''
    set -eu
    mkdir -p ${finance}
    chown -R 1000:1000 ${finance}
    ${pkgs.acl}/bin/setfacl -Rb ${finance}
    ${pkgs.acl}/bin/setfacl -Rk ${finance}
    chmod -R u+rwX,go-rwx ${finance}
    ${pkgs.acl}/bin/setfacl -R -m u:2002:rwX,u:2003:r-X ${finance}
    ${pkgs.findutils}/bin/find ${finance} -type d -exec \
      ${pkgs.acl}/bin/setfacl -m d:u::rwx,d:u:1000:rwx,d:u:2002:rwx,d:u:2003:r-x,d:g::---,d:m::rwx,d:o::--- {} +
  '';
in
{
  users.users.nikita.packages = [ finance-permissions ];
  home-manager.users.nikita.home.sessionVariables.LEDGER_FILE = "${finance}/main.ledger";

  systemd.services.finance-permissions = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "backup-restore.service" ];
    after = [ "backup-restore.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${finance-permissions}/bin/finance-permissions";
    };
  };

  systemd.mounts = [
    {
      what = finance;
      where = "/var/lib/amp/src/finance";
      type = "none";
      options = "bind,rw,nofail";
      requires = [ "finance-permissions.service" ];
      after = [ "finance-permissions.service" ];
      wantedBy = [ "multi-user.target" ];
    }
    {
      what = finance;
      where = "/home/dasha/finance";
      type = "none";
      options = "bind,ro,nofail";
      requires = [ "finance-permissions.service" ];
      after = [ "finance-permissions.service" ];
      wantedBy = [ "multi-user.target" ];
    }
  ];

  systemd.services.amp-runner = {
    requires = [ "var-lib-amp-src-finance.mount" ];
    after = [ "var-lib-amp-src-finance.mount" ];
    environment.LEDGER_FILE = "/var/lib/amp/src/finance/main.ledger";
  };

  systemd.services.dasha-amp-runner = {
    requires = [ "home-dasha-finance.mount" ];
    after = [ "home-dasha-finance.mount" ];
    environment.LEDGER_FILE = "/home/dasha/finance/main.ledger";
  };

  systemd.services.vault-sync = {
    requires = [ "finance-permissions.service" ];
    after = [ "finance-permissions.service" ];
    path = [ pkgs.ledger ];
    environment = {
      FINANCE_DIR = finance;
      LEDGER_FILE = "${finance}/main.ledger";
    };
  };

  services.restic.backups.b2.exclude = [
    "/var/lib/amp/src/finance"
    "/home/dasha/finance"
  ];
}
