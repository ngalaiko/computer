# NixOS-style module system for the exe.dev image, with s6-overlay as the
# supervisor. Declare a system as config — services.*, users.*,
# environment.etc, image.* — and read `build.image` off the evaluation.
{ pkgs }:
let
  inherit (pkgs) lib;

  nixFilesIn =
    dir:
    lib.mapAttrsToList (name: _: dir + "/${name}") (
      lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name) (builtins.readDir dir)
    );

  # Caller's config layered over the base modules: every sibling .nix file and
  # everything in services/ is auto-loaded.
  eval =
    module:
    (lib.evalModules {
      specialArgs = { inherit pkgs; };
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
