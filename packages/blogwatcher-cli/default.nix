# Pre-built blogwatcher-cli binary from its GitHub release tarball.
{ pkgs }:
let
  version = "0.2.1";
  urls = {
    x86_64-linux = {
      url = "https://github.com/JulienTant/blogwatcher-cli/releases/download/v${version}/blogwatcher-cli_linux_amd64.tar.gz";
      hash = "sha256-rbGw1hdQurbubNPifN2U+ybHBWCEqSiSMVl7ImOz1Q0=";
    };
    aarch64-linux = {
      url = "https://github.com/JulienTant/blogwatcher-cli/releases/download/v${version}/blogwatcher-cli_linux_arm64.tar.gz";
      hash = "sha256-J/monGDAep1MeVQDJfDSR5O0nVjCd7HRzSB2M8kAKH4=";
    };
  };
  src =
    urls.${pkgs.stdenv.hostPlatform.system}
      or (throw "unsupported system for blogwatcher-cli: ${pkgs.stdenv.hostPlatform.system}");
in
pkgs.stdenv.mkDerivation {
  pname = "blogwatcher-cli";
  inherit version;

  src = pkgs.fetchurl {
    url = src.url;
    hash = src.hash;
  };

  nativeBuildInputs = [
    pkgs.gnutar
    pkgs.gzip
  ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    mkdir -p $out/bin
    tar xzf $src -C $out/bin blogwatcher-cli
  '';

  meta.mainProgram = "blogwatcher-cli";
}
