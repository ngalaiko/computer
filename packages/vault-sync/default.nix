{ pkgs }:
# Two tiny stdlib-only Python scripts that write vault notes from Letterboxd
# (Movies) and Discogs (Albums). No third-party deps, so they build against the
# pinned python3 directly; a shared vaultlib.py sits on PYTHONPATH. Exposes
# `vault-sync-letterboxd` and `vault-sync-discogs`.
let
  inherit (pkgs) lib python3 makeWrapper;
in
pkgs.stdenv.mkDerivation {
  pname = "vault-sync";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];

  # scripts are stdlib-only; just syntax-check them at build time.
  doCheck = true;
  checkPhase = ''
    ${python3}/bin/python3 -m py_compile vaultlib.py letterboxd.py discogs.py
  '';

  installPhase = ''
    mkdir -p $out/libexec $out/bin
    cp vaultlib.py letterboxd.py discogs.py $out/libexec/
    for s in letterboxd discogs; do
      makeWrapper ${python3}/bin/python3 $out/bin/vault-sync-$s \
        --add-flags $out/libexec/$s.py \
        --set PYTHONPATH $out/libexec
    done
  '';

  meta = {
    description = "Sync Letterboxd + Discogs into the Obsidian vault as notes";
    mainProgram = "vault-sync-letterboxd";
    license = lib.licenses.mit;
  };
}
