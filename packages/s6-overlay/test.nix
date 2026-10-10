{ pkgs }:
let
  inherit (pkgs) lib;
  cfg =
    (lib.evalModules {
      specialArgs = { inherit pkgs; };
      modules = [
        ../../modules/exedev/s6.nix
        {
          options.image = lib.mkOption { type = lib.types.attrs; };
          options.users = lib.mkOption { type = lib.types.attrs; };
          options.environment = lib.mkOption { type = lib.types.attrs; };
          config.s6.services.probe.run = ''
            exec ${pkgs.s6}/bin/s6-setuidgid amp ${pkgs.runtimeShell} -c '
              printf "uid=%s gid=%s env=%s\\n" "$(${pkgs.coreutils}/bin/id -u)" "$(${pkgs.coreutils}/bin/id -g)" "$S6_PROBE"
              exec ${lib.getBin pkgs.s6-portable-utils}/bin/s6-pause
            '
          '';
          config.s6.services.environment = {
            type = "oneshot";
            run = ''
              printf 'env=%s extra=%s multiline=%s\n' "$S6_PROBE" "''${S6_LOCAL_ONLY-unset}" "$S6_MULTILINE"
            '';
          };
        }
      ];
    }).config;
in
pkgs.testers.runNixOSTest {
  name = "exedev-s6-runtime";
  nodes.machine = {
    users.groups.amp.gid = 2002;
    users.users.amp = {
      isSystemUser = true;
      uid = 2002;
      group = "amp";
    };
  };
  testScript = ''
    machine.start()
    machine.succeed("test ! -e /command && test ! -e /package")
    machine.succeed("mkdir -p /run/s6; S6_PROBE=from-container ${lib.getBin pkgs.s6-portable-utils}/bin/s6-dumpenv /run/s6/container_environment")
    machine.succeed("printf 'first\\nsecond\\n' > /run/s6/container_environment/S6_MULTILINE")
    machine.succeed("S6_PROBE=wrong S6_LOCAL_ONLY=leaked ${pkgs.runtimeShell} ${builtins.elemAt cfg.image.rootPaths 1}/etc/s6-overlay/s6-rc.d/environment/up")
    assert machine.succeed("cat /var/log/environment/current") == "env=from-container extra=unset multiline=first\nsecond\n"
    machine.succeed("S6_KEEP_ENV=1 S6_PROBE=inherited S6_LOCAL_ONLY=kept S6_MULTILINE=local ${pkgs.runtimeShell} ${builtins.elemAt cfg.image.rootPaths 1}/etc/s6-overlay/s6-rc.d/environment/up")
    assert machine.succeed("tail -n 1 /var/log/environment/current") == "env=inherited extra=kept multiline=local\n"
    machine.succeed("cp -rL ${cfg.s6.build.serviceTree} /run/service; chmod -R u+w /run/service")
    machine.succeed("S6_PROBE=wrong ${pkgs.s6}/bin/s6-svscan /run/service >/tmp/svscan.log 2>&1 &")
    machine.wait_until_succeeds("grep -q 'uid=2002 gid=2002 env=from-container' /var/log/probe/current")
    machine.succeed("${pkgs.s6}/bin/s6-svc -r /run/service/probe")
    machine.wait_until_succeeds("test $(grep -c 'uid=2002 gid=2002 env=from-container' /var/log/probe/current) -ge 2")
    machine.succeed("${pkgs.s6}/bin/s6-svc -d /run/service/probe; ${pkgs.s6}/bin/s6-svc -wd -T 10000 /run/service/probe")
    machine.succeed("${pkgs.s6}/bin/s6-svscanctl -t /run/service")
  '';
}
