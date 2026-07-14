# Shelley — exe.dev's coding agent (prebuilt release binary).
{ pkgs }:
let
  version = "0.634.915524700";
  perSystem = {
    x86_64-linux = {
      arch = "amd64";
      hash = "sha256-bWNe+raRhq3QsLSZG6tYBO3PDqjTQWjpbNcheg6/x8I=";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-j0jMpYHwBcCziT8db53lCaStoAx1mIR7kebRDW3ouIQ=";
    };
  };
  target =
    perSystem.${pkgs.stdenv.hostPlatform.system}
      or (throw "unsupported Shelley platform: ${pkgs.stdenv.hostPlatform.system}");
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "shelley";
  inherit version;
  src = pkgs.fetchurl {
    url = "https://github.com/boldsoftware/shelley/releases/download/v${version}/shelley_linux_${target.arch}";
    hash = target.hash;
  };
  dontUnpack = true;
  installPhase = ''
    install -Dm755 $src $out/bin/shelley
  '';
  meta = {
    description = "Mobile-friendly web-based coding agent for exe.dev";
    homepage = "https://github.com/boldsoftware/shelley";
    license = pkgs.lib.licenses.asl20;
    mainProgram = "shelley";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
