{ pkgs, config }:
let
  inherit (pkgs) lib;
  restore = "backup-restore.service";
  vault = "vault-permissions.service";
  dependencies = {
    "tailscaled.service" = restore;
    "home-manager-nikita.service" = restore;
    "amp-runner.service" = [
      restore
      "var-lib-amp-src-finance.mount"
    ];
    "finance-permissions.service" = restore;
    "var-lib-amp-src-finance.mount" = "finance-permissions.service";
    "home-dasha-finance.mount" = "finance-permissions.service";
    "dasha-amp-runner.service" = [
      restore
      "home-dasha-finance.mount"
    ];
    "vault-permissions.service" = restore;
    "obsidian-sync.service" = vault;
    "wherenow.service" = vault;
    "vault-sync.service" = [
      vault
      "finance-permissions.service"
    ];
  }
  // lib.mapAttrs' (
    name: _: lib.nameValuePair "ingress-${name}.service" restore
  ) config.services.ingress.tenants;
  units = pkgs.writeText "restore-dependencies.json" (
    builtins.toJSON (
      lib.mapAttrs (name: dependency: {
        dependencies = lib.toList dependency;
        text = builtins.unsafeDiscardStringContext config.systemd.units.${name}.text;
      }) dependencies
    )
  );
in
pkgs.runCommand "backup-dependencies-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python - ${units} <<'PY'
  import json
  import sys

  with open(sys.argv[1]) as source:
      units = json.load(source)
  failures = []
  for name, unit in units.items():
      for directive in ("Requires", "After"):
          dependencies = {
              dependency
              for line in unit["text"].splitlines()
              if line.startswith(directive + "=")
              for dependency in line.split("=", 1)[1].split()
          }
          for dependency in unit["dependencies"]:
              if dependency not in dependencies:
                  failures.append(f"{name}: missing {directive}={dependency}")
  if failures:
      sys.exit("\n".join(failures))
  PY
  touch $out
''
