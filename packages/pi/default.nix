{ pkgs }:
let
  inherit (pkgs) lib;
in
pkgs.buildNpmPackage {
  pname = "pi-coding-agent";
  version = "0.83.0";

  # Published npm tarball with a prebuilt dist/. It ships an npm-shrinkwrap.json
  # but omits the integrity field for its three sibling @earendil-works/* deps,
  # which prefetch-npm-deps rejects ("non-git dependencies should have
  # associated integrity"). ./npm-shrinkwrap.json is that lockfile with those
  # integrities filled in from the registry; we drop it in under both lockfile
  # names so `npm ci` and fetchNpmDeps read the same pinned tree.
  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-0.83.0.tgz";
    hash = "sha512-uYhF+FsZxogoSX/AxBcUdiY+ZklubwaXyAoEGA2eQwsHcyEAhUYIKh/WLXe/a8+k8eTCmxb+ZN2Zo9mzQtzbWw==";
  };
  sourceRoot = "package";

  postPatch = ''
    cp ${./npm-shrinkwrap.json} npm-shrinkwrap.json
    cp ${./npm-shrinkwrap.json} package-lock.json
    # The shipped shrinkwrap is production-only (no devDependencies), but
    # package.json still lists them; drop them so `npm ci` sees a consistent
    # tree instead of trying to fetch dev-only packages (e.g. @types/*) that
    # aren't in the lock — which fails in the offline sandbox.
    ${pkgs.jq}/bin/jq 'del(.devDependencies)' package.json > package.json.tmp
    mv package.json.tmp package.json
  '';

  npmDepsHash = "sha256-G8+n5dBfPI/nDn3j975yaLZaC6u13IEyzMcnkp2xKmQ=";

  # engines requires node >= 22.19.0; the pinned nodejs_22 (22.22) qualifies.
  nodejs = pkgs.nodejs_22;

  # dist/ is prebuilt in the tarball and the build toolchain (tsgo, bun) isn't
  # packaged, so there's nothing to compile; don't run npm lifecycle scripts
  # either (upstream's own install guidance is --ignore-scripts). --omit=dev
  # because the shipped shrinkwrap is production-only: devDependencies (e.g.
  # @types/*) have no locked resolution, so a default `npm ci` would try to
  # fetch them over the network and fail in the sandbox.
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
