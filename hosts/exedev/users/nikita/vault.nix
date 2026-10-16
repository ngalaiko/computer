{ pkgs, lib, ... }:
let
  home = "/home/nikita";
  vault = "${home}/Vault";
  obsidian-headless = import ../../../../packages/obsidian-headless { inherit pkgs; };
  wherenow = import ../../../../packages/wherenow { inherit pkgs; };
  vault-sync = import ../../../../packages/vault-sync { inherit pkgs; };
  obsidian-sync = pkgs.writeShellScriptBin "obsidian-sync" ''
    set -eu
    exec ${obsidian-headless}/bin/ob sync --path "''${OBSIDIAN_VAULT_DIR:-${vault}}" "$@"
  '';
  # Only the Vault is shared. Agents can traverse nikita's home, but this
  # doesn't grant access to private app credentials under ~/.config.
  vault-permissions = pkgs.writeShellScriptBin "vault-permissions" ''
    set -eu
    ${pkgs.acl}/bin/setfacl -m u:2001:--x,u:2002:--x ${home}
    mkdir -p ${vault}
    chown -R 1000:1000 ${vault}
    ${pkgs.acl}/bin/setfacl -Rb ${vault}
    ${pkgs.acl}/bin/setfacl -Rk ${vault}
    chmod -R u+rwX,go-rwx ${vault}
    ${pkgs.acl}/bin/setfacl -R -m u:1000:rwX,u:2001:rwX,u:2002:rwX ${vault}
    ${pkgs.findutils}/bin/find ${vault} -type d -exec \
      ${pkgs.acl}/bin/setfacl -m d:u::rwx,d:u:1000:rwx,d:u:2001:rwx,d:u:2002:rwx,d:g::---,d:m::rwx,d:o::--- {} +
  '';
  vaultSyncCrontab = pkgs.writeText "vault-sync-crontab" ''
    17 * * * * ${vault-sync}/bin/vault-sync-letterboxd
    47 */6 * * * ${vault-sync}/bin/vault-sync-discogs
  '';
  requireVault = ''
    if [ ! -d ${vault}/.obsidian ]; then
      echo "${vault} not configured yet; run ob login + ob sync-setup as nikita. Retrying." >&2
      exit 1
    fi
  '';
  # Runs as nikita after the Vault's ACLs are in place; failures retry.
  asNikita =
    attrs:
    lib.recursiveUpdate {
      wantedBy = [ "multi-user.target" ];
      wants = [ "vault-permissions.service" ];
      after = [ "vault-permissions.service" ];
      path = [ "/etc/profiles/per-user/nikita" ];
      environment = {
        HOME = home;
        OBSIDIAN_VAULT_DIR = vault;
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
        NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt";
      };
      serviceConfig = {
        User = "nikita";
        WorkingDirectory = home;
        Restart = "always";
        RestartSec = 30;
      };
      startLimitIntervalSec = 0;
    } attrs;
in
{
  users.users.nikita.packages = [
    obsidian-headless
    obsidian-sync
    vault-sync
    vault-permissions
    pkgs.acl
  ];

  # Reapplied after restore and whenever this unit changes; ACL defaults keep
  # newly created notes shared regardless of the creating account's umask.
  systemd.services.vault-permissions = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "backup-restore.service" ];
    after = [ "backup-restore.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${vault-permissions}/bin/vault-permissions";
    };
  };

  # Service names kept from the assistant-owned Vault.
  systemd.services.assistant-obsidian-sync = asNikita {
    script = requireVault + ''
      exec ${obsidian-headless}/bin/ob sync --path ${vault} --continuous
    '';
  };

  # Served through /assistant/wherenow on loopback port 8085.
  systemd.services.assistant-wherenow = asNikita {
    environment.PORT = "8085";
    serviceConfig.RestartSec = 10;
    script = requireVault + ''
      envfile=${home}/.config/wherenow/env
      if [ ! -f "$envfile" ]; then
        echo "assistant-wherenow: $envfile missing; place TOKEN=... (see README). Retrying." >&2
        exit 1
      fi
      set -a
      . "$envfile"
      set +a
      if [ -z "''${TOKEN:-}" ]; then
        echo "assistant-wherenow: TOKEN unset in $envfile. Retrying." >&2
        exit 1
      fi
      exec ${wherenow}/bin/wherenow --vault-dir=${vault} --tz=Europe/Stockholm
    '';
  };

  # Letterboxd is public (hourly); Discogs self-skips without a token (every 6h).
  # Runtime secrets are exported, never passed in argv or baked into the store.
  systemd.services.assistant-vault-sync = asNikita {
    script = requireVault + ''
      envfile=${home}/.config/vault-sync/env
      if [ -f "$envfile" ]; then
        set -a
        . "$envfile"
        set +a
      else
        echo "assistant-vault-sync: $envfile missing; Discogs sync skipped until DISCOGS_TOKEN is placed (see README)." >&2
      fi
      exec ${pkgs.supercronic}/bin/supercronic ${vaultSyncCrontab}
    '';
  };
}
