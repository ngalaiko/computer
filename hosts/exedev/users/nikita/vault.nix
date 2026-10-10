{ pkgs, ... }:
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
      sleep 30
      exit 1
    fi
  '';
  asNikita = ''
    exec /command/s6-setuidgid nikita \
      env \
        HOME=${home} \
        USER=nikita \
        SHELL=/bin/sh \
        PATH=/etc/profiles/per-user/nikita/bin:/nix/var/nix/profiles/default/bin:/bin:/sbin:/usr/bin \
        SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
        NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
        NODE_EXTRA_CA_CERTS=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
        OBSIDIAN_VAULT_DIR=${vault} \
  '';
in
{
  users.users.nikita.packages = [
    obsidian-headless
    obsidian-sync
    vault-sync
    vault-permissions
    pkgs.acl
  ];
  services.backup.paths = [
    vault
    "${home}/.config/obsidian-headless"
    "${home}/.config/vault-sync"
    "${home}/.config/wherenow"
  ];

  # Reapply after restore and on deploy; ACL defaults keep newly created notes
  # shared regardless of the creating account's umask.
  s6.services.vault-permissions = {
    type = "oneshot";
    reactivate = true;
    dependencies = [ "backup-restore" ];
    run = "${vault-permissions}/bin/vault-permissions";
  };

  # Keep service names stable for in-place upgrades and existing log paths.
  s6.services.assistant-obsidian-sync = {
    dependencies = [ "vault-permissions" ];
    run =
      requireVault
      + asNikita
      + ''
        ${obsidian-headless}/bin/ob sync --path ${vault} --continuous
      '';
  };

  # Still served through /assistant/wherenow on loopback port 8085.
  s6.services.assistant-wherenow = {
    dependencies = [ "vault-permissions" ];
    run =
      requireVault
      + ''
        envfile=${home}/.config/wherenow/env
        if [ ! -f "$envfile" ]; then
          echo "assistant-wherenow: $envfile missing; place TOKEN=... (see README). Retrying." >&2
          sleep 10
          exit 1
        fi
        set -a
        . "$envfile"
        set +a
        if [ -z "''${TOKEN:-}" ]; then
          echo "assistant-wherenow: TOKEN unset in $envfile. Retrying." >&2
          sleep 10
          exit 1
        fi
      ''
      + asNikita
      + ''
        PORT=8085 \
        ${wherenow}/bin/wherenow --vault-dir=${vault} --tz=Europe/Stockholm
      '';
  };

  # Letterboxd is public (hourly); Discogs self-skips without a token (every 6h).
  # Runtime secrets are exported, never passed in argv or baked into the store.
  s6.services.assistant-vault-sync = {
    dependencies = [ "vault-permissions" ];
    run =
      requireVault
      + ''
        envfile=${home}/.config/vault-sync/env
        if [ -f "$envfile" ]; then
          set -a
          . "$envfile"
          set +a
        else
          echo "assistant-vault-sync: $envfile missing; Discogs sync skipped until DISCOGS_TOKEN is placed (see README)." >&2
        fi
      ''
      + asNikita
      + ''
        ${pkgs.supercronic}/bin/supercronic ${vaultSyncCrontab}
      '';
  };
}
