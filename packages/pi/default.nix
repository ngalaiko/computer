{ pkgs }:
let
  inherit (pkgs) lib;
in
pkgs.buildNpmPackage {
  pname = "pi-coding-agent";
  version = "1.1.0";

  # Published npm tarball with a prebuilt dist/ and no lockfile.
  # ./package-lock.json is generated from its package.json (devDependencies
  # dropped) via `npm install --package-lock-only --omit=dev`.
  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-1.1.0.tgz";
    hash = "sha512-SeEi/4hdcHNgA9UWlefZl7ZZpm3dzi2OoxNjDHsBJ9o298LNOtbL4DGKgitlEj6uCTccvtw6f2hlCkTPVJ2RXg==";
  };
  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    # package.json lists devDependencies absent from the production-only lock;
    # drop them so offline `npm ci` doesn't try to fetch them.
    ${pkgs.jq}/bin/jq 'del(.devDependencies)' package.json > package.json.tmp
    mv package.json.tmp package.json
  '';

  npmDepsHash = "sha256-fpx4E33nK2ypUiFhp7Om0I4ukAW1n726s/nYqefeyOk=";

  # engines requires node >= 22.19.0; the pinned nodejs_22 (22.22) qualifies.
  nodejs = pkgs.nodejs_22;

  # dist/ is prebuilt in the tarball and the build toolchain (tsgo, bun) isn't
  # packaged, so there's nothing to compile; don't run npm lifecycle scripts
  # either (upstream's own install guidance is --ignore-scripts). --omit=dev
  # because the lock is production-only.
  dontNpmBuild = true;
  npmFlags = [
    "--ignore-scripts"
    "--omit=dev"
  ];

  meta = {
    description = "Pi: an open-source, BYOK CLI coding agent";
    homepage = "https://github.com/earendil-works/pi";
    license = lib.licenses.mit;
    mainProgram = "pi";
  };
}
