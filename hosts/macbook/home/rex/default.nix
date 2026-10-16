{
  config,
  lib,
  pkgs,
  ...
}:
let
  # the app comes from outside nix; link its cli
  rex = "/Applications/Rex Beta.app/Contents/Helpers/Rex Server.app/Contents/MacOS/rex";
in
{
  home.packages = [
    (pkgs.runCommand "rex" { } ''
      mkdir -p $out/bin
      ln -s "${rex}" $out/bin/rex
    '')
  ];

  xdg.configFile."rex/init.lua".source = ./init.lua;

  targets.darwin.defaults."com.superlogical.rex"."Workspace.terminalStartupCommand" =
    "/etc/profiles/per-user/${config.home.username}/bin/fish";

  # rex does not watch init.lua
  home.activation.rexConfigReload = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ -x "${rex}" ]; then
      run "${rex}" --autostart=false config reload || true
    fi
  '';
}
