# Open Terminal — "a computer you can curl": a REST-API shell (commands,
# files, code execution) that Open WebUI drives as its execution environment.
# Distributed as a wheel only, not in nixpkgs; built against unstable's
# python3Packages (its dep floors, e.g. aiofiles>=25.1, exceed nixpkgs-25.11).
{ pkgs }:
let
  ps = pkgs.python3Packages;
in
ps.buildPythonApplication rec {
  pname = "open-terminal";
  version = "0.11.34";
  format = "wheel";

  src = ps.fetchPypi {
    pname = "open_terminal";
    inherit version format;
    dist = "py3";
    python = "py3";
    abi = "none";
    platform = "any";
    hash = "sha256-ibiUAZnIyWEucapKGCiYn71OEaO+ZW+UXbwJ/Xc+F2g=";
  };

  dependencies = with ps; [
    aiofiles
    click
    fastapi
    httpx
    ipykernel
    nbclient
    openpyxl
    pypdf
    python-docx
    python-multipart
    python-pptx
    striprtf
    xlrd
    # uvicorn[standard]
    uvicorn
    uvloop
    httptools
    websockets
    watchfiles
    python-dotenv
    pyyaml
    # the declared "mcp" extra, so MCP clients can drive it too
    fastmcp
  ];

  pythonImportsCheck = [ "open_terminal" ];

  meta = {
    description = "Open Terminal — self-hosted terminal for AI agents over a REST API";
    homepage = "https://github.com/open-webui/open-terminal";
    license = pkgs.lib.licenses.mit;
    mainProgram = "open-terminal";
  };
}
