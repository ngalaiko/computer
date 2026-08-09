{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;

  rootfs = config.build.rootfs;
  fixups = config.build.activationFixups;
  serviceTree = config.s6.build.serviceTree;
  oneshots = config.s6.build.oneshots;
  reactivate = config.s6.build.reactivate;

  # ABI version: init-wrapper and activate share this contract. Bump on a
  # breaking change to the gen/ layout.
  version = "1";

  # top-level rootfs entries activation must never touch: pseudo/runtime/state
  # dirs (never overlaid or pruned), the store itself, and the s6-overlay
  # runtime (command/package/init) — bumping s6-overlay is a base change that
  # goes through an image rebuild + recreate, not a live switch. `init-wrapper`
  # is deliberately NOT excluded, so a switch ships the current boot handoff.
  excludes = [
    "proc"
    "sys"
    "dev"
    "run"
    "nix"
    "var"
    "home"
    "root"
    "tmp"
    "command"
    "package"
    "init"
  ];

  # managed rel-paths (files + symlinks, dirs implied) minus the excludes.
  manifest = pkgs.runCommand "system-manifest" { } ''
    cd ${rootfs}
    find . -mindepth 1 \( -type f -o -type l \) -printf '%P\n' \
      | grep -Ev '^(${lib.concatStringsSep "|" excludes})(/|$)' \
      | LC_ALL=C sort > $out
  '';

  reactivateFile = pkgs.writeText "reactivate" (lib.concatStrings (map (n: n + "\n") reactivate));

  activate = pkgs.runCommand "activate" { } ''
    substitute ${./activate.sh} $out \
      --subst-var-by bash ${pkgs.bashInteractive} \
      --subst-var-by coreutils ${pkgs.coreutils} \
      --subst-var-by gnugrep ${pkgs.gnugrep} \
      --subst-var-by diffutils ${pkgs.diffutils} \
      --subst-var-by utilLinux ${pkgs.util-linux} \
      --subst-var-by nix ${pkgs.nix} \
      --subst-var-by s6 ${config.s6.package}/command
    chmod +x $out
    ${pkgs.bashInteractive}/bin/bash -n $out
  '';

  # The generation: a self-contained, GC-rootable closure. The symlinks pull
  # rootfs/service/oneshots/fixups (and their whole closures) into build.system,
  # so `nix copy .#system` ships everything and the system profile roots it all.
  system = pkgs.runCommand "computer-system" { } ''
    mkdir -p $out
    ln -s ${rootfs}      $out/rootfs
    ln -s ${serviceTree} $out/service
    ln -s ${oneshots}    $out/oneshots
    ln -s ${fixups}      $out/fixups
    cp ${manifest}       $out/manifest
    cp ${reactivateFile} $out/reactivate
    printf '%s\n' ${version} > $out/version
    install -m0755 ${activate} $out/activate
  '';
in
{
  options.build.system = mkOption {
    type = types.package;
    readOnly = true;
    description = "The in-place-deployable system generation (nix copy + <gen>/activate switch).";
  };

  config.build.system = system;
}
