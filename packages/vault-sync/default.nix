{
  lib,
  stdenv,
  python3,
  ledger,
  makeWrapper,
}:
# Stdlib-only exporters for Letterboxd, Discogs, and Ledger.
stdenv.mkDerivation {
  pname = "vault-sync";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];

  nativeCheckInputs = [ ledger ];
  doCheck = true;
  checkPhase = ''
    ${python3}/bin/python3 -m py_compile vaultlib.py letterboxd.py discogs.py finance.py
    ${python3}/bin/python3 -m unittest discover -p test_finance.py
  '';

  installPhase = ''
    mkdir -p $out/libexec $out/bin
    cp vaultlib.py letterboxd.py discogs.py finance.py $out/libexec/
    for s in letterboxd discogs finance; do
      makeWrapper ${python3}/bin/python3 $out/bin/vault-sync-$s \
        --add-flags $out/libexec/$s.py \
        --set PYTHONPATH $out/libexec \
        --prefix PATH : ${lib.makeBinPath [ ledger ]}
    done
  '';

  meta = {
    description = "Sync Letterboxd, Discogs, and Ledger into the Obsidian vault";
    mainProgram = "vault-sync-letterboxd";
    license = lib.licenses.mit;
  };
}
