{ pkgs }:
let
  inherit (pkgs) lib;

  nodeModules = pkgs.stdenv.mkDerivation {
    pname = "pilegram-node-modules";
    version = "0.0.0";
    src = ./.;
    nativeBuildInputs = [ pkgs.bun ];
    dontConfigure = true;
    buildPhase = ''
      export HOME="$TMPDIR"
      bun install --frozen-lockfile --no-progress --production
    '';
    installPhase = ''
      rm -rf node_modules/.cache
      cp -R node_modules "$out"
    '';
    dontFixup = true;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    # Per-system: node_modules carries platform-specific native optional deps.
    outputHash =
      {
        aarch64-linux = "sha256-eQ2bTig+2NQOJ7+GJpVoANc14+0nwq5/cMYa4s3/IMk=";
        x86_64-linux = "sha256-VkzkAui11dqgfgXeUAwhxFvzujCrf/72yZORFWqKONE=";
      }
      .${pkgs.stdenv.hostPlatform.system};
  };
in
pkgs.stdenv.mkDerivation {
  pname = "pilegram";
  version = "0.0.0";
  src = ./.;
  nativeBuildInputs = [ pkgs.makeWrapper ];
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    mkdir -p "$out/libexec/pilegram"
    cp -R src vendor package.json bun.lock "$out/libexec/pilegram/"
    # Bun resolves ESM bare imports via the importing module's realpath; keep a
    # real node_modules dir here rather than a symlink to the FOD.
    cp -R ${nodeModules} "$out/libexec/pilegram/node_modules"
    makeWrapper ${pkgs.bun}/bin/bun "$out/bin/pilegram" \
      --add-flags "run $out/libexec/pilegram/src/index.ts" \
      --prefix PATH : ${
        lib.makeBinPath [
          pkgs.ffmpeg
          pkgs.whisper-cpp
        ]
      } \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ]}
  '';
  meta = {
    description = "pi ⇄ Telegram gateway";
    mainProgram = "pilegram";
  };
}
