# agent-browser CLI from its prebuilt npm tarball (self-contained native
# binary per platform; no npm deps). We expose the native binary directly —
# the shipped .js is only a node dispatcher for npx/Windows.
{ pkgs }:
let
  version = "0.26.0";
  bin =
    {
      x86_64-linux = "agent-browser-linux-x64";
      aarch64-linux = "agent-browser-linux-arm64";
    }
    .${pkgs.stdenv.hostPlatform.system}
      or (throw "unsupported system for agent-browser: ${pkgs.stdenv.hostPlatform.system}");
in
pkgs.stdenv.mkDerivation {
  pname = "agent-browser";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/agent-browser/-/agent-browser-${version}.tgz";
    hash = "sha256-ikjPQRDX3CwSwcTW0l4Lq9+jFgS1N/Bd8NyDX+L4VL8=";
  };
  sourceRoot = "package";

  nativeBuildInputs = [ pkgs.autoPatchelfHook ];

  dontBuild = true;
  installPhase = ''
    runHook preInstall
    dst=$out/libexec/agent-browser
    mkdir -p $dst/bin $out/bin
    install -Dm755 bin/${bin} $dst/bin/${bin}
    for d in skills skill-data; do
      [ -e "$d" ] && cp -r "$d" "$dst/"
    done
    ln -s $dst/bin/${bin} $out/bin/agent-browser
    runHook postInstall
  '';

  meta.mainProgram = "agent-browser";
}
