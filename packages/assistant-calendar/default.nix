{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
  sops,
}:
let
  python = python3.withPackages (
    ps:
    let
      # CalDAV supports requests as a fallback. The pinned niquests dependency's
      # urllib3-future fails its TLS/gzip tests; keep checks, use that backend.
      caldav = (ps.caldav.override { niquests = ps.requests; }).overridePythonAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace pyproject.toml --replace-fail '"niquests"' '"requests"'
        '';
      });
    in
    [
      caldav
      ps.icalendar
    ]
  );
in
stdenvNoCC.mkDerivation {
  pname = "assistant-calendar";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/libexec $out/bin
    # Do not shadow Python's stdlib calendar module during dependency imports.
    cp calendar.py $out/libexec/assistant_calendar.py
    makeWrapper ${python}/bin/python3 $out/bin/assistant-calendar \
      --add-flags $out/libexec/assistant_calendar.py \
      --prefix PATH : ${lib.makeBinPath [ sops ]}
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/assistant-calendar --help
    for command in calendars events get create update delete; do
      $out/bin/assistant-calendar "$command" --help
    done
    # Missing configuration must fail locally, without decrypting or connecting.
    unset ICLOUD_ACCOUNT ASSISTANT_SECRETS_FILE
    if $out/bin/assistant-calendar calendars 2>error.json; then
      echo "Calendar unexpectedly accepted missing configuration" >&2
      exit 1
    fi
    ${python}/bin/python3 -c 'import json; assert json.load(open("error.json")) == {"error": "Configure ICLOUD_ACCOUNT and an absolute external ASSISTANT_SECRETS_FILE path."}'
  '';

  meta = {
    description = "CalDAV JSON CLI using external SOPS credentials";
    mainProgram = "assistant-calendar";
  };
}
