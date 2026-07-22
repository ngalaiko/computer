# Open WebUI Computer (cptr) — "your computer, from anywhere": files, editor,
# terminal, git, and chat over the machine it runs on. Distributed as a wheel
# only (bundled frontend), not in nixpkgs. Its dep floors (fastapi>=0.128.8)
# exceed nixpkgs-25.11, so build against unstable's python3Packages.
{ pkgs }:
let
  ps = pkgs.python3Packages;
in
ps.buildPythonApplication rec {
  pname = "cptr";
  version = "0.9.12";
  format = "wheel";

  src = ps.fetchPypi {
    inherit pname version format;
    dist = "py3";
    python = "py3";
    abi = "none";
    platform = "any";
    hash = "sha256-J5hUwuAOOhtELtYLP4IiVF72kLr4vzBbMoTBMj2vhX8=";
  };

  # unstable ships cryptography 49; cptr's metadata caps at <49. The cap is
  # conservative — relax it rather than pin an older cryptography + rebuild world.
  pythonRelaxDeps = [ "cryptography" ];

  dependencies = with ps; [
    aiosqlite
    alembic
    bcrypt
    click
    cryptography
    fastapi
    httpx
    loguru
    pyjwt
    python-dateutil
    python-socketio
    sqlalchemy
    greenlet # sqlalchemy[asyncio]
    truststore
    watchdog
    # fastapi[standard] runtime pieces cptr may import
    uvicorn
    uvloop
    httptools
    websockets
    watchfiles
    python-dotenv
    jinja2
    python-multipart
    email-validator
    # pyyaml is imported at startup (skills.py) but missing from the wheel's
    # metadata; the rest back cptr's optional extras (its declared "all" set):
    # file preview, coding-agent backend, MCP, and PAM login.
    pyyaml
    pillow
    lxml
    pypdf
    python-docx
    openpyxl
    python-pptx
    xlrd
    striprtf
    pydub
    mcp
    python-pam
    claude-agent-sdk
  ];

  pythonImportsCheck = [ "cptr" ];

  meta = {
    description = "Open WebUI Computer — your machine in a browser (files, terminal, git, chat)";
    homepage = "https://docs.openwebui.com/ecosystem/computer/";
    license = {
      shortName = "open-use";
      fullName = "Open Use License (Elastic License 2.0 + attribution)";
      free = false;
      redistributable = true;
    };
    mainProgram = "cptr";
  };
}
