{ pkgs }:
let
  inherit (pkgs) lib;
in
pkgs.buildNpmPackage {
  pname = "obsidian-headless";
  version = "0.0.14";

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/obsidian-headless/-/obsidian-headless-0.0.14.tgz";
    hash = "sha512-S1d/hxLKvCUG2g5tRyXFkzPqMs3Ntw1tDyzoF2yfHGRuB4B+Mi3X2vgT8LbfQKrkEEi3LfJRdXtYzAVHcbpccw==";
  };
  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-Pcy6hxgc9MyTe/a7bE4pMtXjG9hx4HNwZgbfIzTtVRQ=";

  nodejs = pkgs.nodejs_22;
  dontNpmBuild = true;
  npmFlags = [
    "--ignore-scripts"
    "--omit=dev"
  ];

  meta = {
    description = "Headless client for Obsidian Sync and Publish";
    homepage = "https://github.com/obsidianmd/obsidian-headless";
    license = lib.licenses.mit;
    mainProgram = "ob";
  };
}
