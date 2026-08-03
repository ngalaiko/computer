{ pkgs }:
let
  inherit (pkgs) lib;
  nodejs = pkgs.nodejs_22;
  # reuse the pi-coding-agent we already build for the CLI rather than fetching
  # a second copy; it satisfies the gateway's peer import.
  pi = import ../pi { inherit pkgs; };
in
pkgs.buildNpmPackage {
  pname = "pi-gateway";
  version = "1.10.1";

  # Wrapper package (see ./package.json): @gamalan/pi-gateway plus the one peer
  # pi neither installs (--omit=peer) nor otherwise provides — @sinclair/typebox
  # (pi ships the unrelated unscoped `typebox`). npm hoists them and the
  # gateway's deps (better-sqlite3, ws) into one node_modules. The other peer,
  # @earendil-works/pi-coding-agent, is symlinked in from packages/pi in
  # postInstall — installing it via npm drags in @earendil-works/* entries whose
  # registry integrity npm omits (they come from pi-coding-agent's bundled
  # shrinkwrap), which breaks the offline npm cache.
  src = ./.;
  npmDepsHash = "sha256-R7r1SMeUm9r7jycRpSOfbANCiHcbPqX3lX10o6tADwA=";

  inherit nodejs;

  # better-sqlite3 (the gateway's session store) is a native addon; compile it
  # from source against this nodejs via node-gyp (needs python3). build_from_source
  # stops its install script reaching for a prebuilt over the network, which the
  # sandbox blocks. --legacy-peer-deps: the pi-coding-agent peer is intentionally
  # absent from the lockfile (provided by the symlink below).
  nativeBuildInputs = [
    pkgs.python3
    pkgs.makeWrapper
  ];
  npmFlags = [ "--legacy-peer-deps" ];
  npm_config_build_from_source = "true";

  # the wrapper has no build step or bin of its own.
  dontNpmBuild = true;

  postInstall = ''
    root=$out/lib/node_modules/pi-gateway-dist/node_modules

    # provide the pi-coding-agent peer from the already-built pi package so the
    # daemon's `import "@earendil-works/pi-coding-agent"` resolves (node follows
    # the symlink to its real store path and resolves its deps from there).
    mkdir -p "$root/@earendil-works"
    ln -s ${pi}/lib/node_modules/@earendil-works/pi-coding-agent \
      "$root/@earendil-works/pi-coding-agent"

    # expose the gateway's daemon entry (what `pi-gateway start` spawns) as a
    # foreground-runnable binary for the s6 service.
    entry=$(find "$root/@gamalan/pi-gateway" -path '*/dist/index.js' | head -n1)
    if [ -z "$entry" ]; then
      echo "pi-gateway: daemon entry not found under $root" >&2
      exit 1
    fi
    makeWrapper ${nodejs}/bin/node $out/bin/pi-gateway-daemon --add-flags "$entry"
  '';

  meta = {
    description = "Self-contained @gamalan/pi-gateway (pi Telegram/chat bridge) with its pi peer deps bundled";
    homepage = "https://www.npmjs.com/package/@gamalan/pi-gateway";
    license = lib.licenses.mit;
    mainProgram = "pi-gateway-daemon";
  };
}
