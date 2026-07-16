{
  pkgs,
  specialArgs ? { },
}:
let
  inherit (pkgs) lib;

  nixFilesIn =
    dir:
    lib.mapAttrsToList (name: _: dir + "/${name}") (
      lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name) (builtins.readDir dir)
    );

  # auto-loads every sibling .nix + services/*.nix as modules.
  eval =
    module:
    (lib.evalModules {
      specialArgs = {
        inherit pkgs;
      }
      // specialArgs;
      modules = [
        module
      ]
      ++ lib.filter (p: baseNameOf p != "default.nix") (nixFilesIn ./.)
      ++ nixFilesIn ./services;
    }).config;
in
{
  inherit eval;
}
