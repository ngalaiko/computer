{ inputs, pkgs, ... }:
let
  unstable = import inputs.nixpkgs-unstable { inherit (pkgs.stdenv.hostPlatform) system; };

  # The Vercel CLI is no longer in nixpkgs (nodePackages was removed 2026-03-03).
  # Its published npm tarball ships a fully esbuild-bundled dist/ that runs
  # standalone with no node_modules, so we just wrap dist/vc.js with node.
  vercel-cli = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "vercel-cli";
    version = "59.3.0";

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/vercel/-/vercel-${finalAttrs.version}.tgz";
      hash = "sha256-R/GdZWtpgAzdQwvcCX2GtxT1TcNyzhjxUY6+q2mBUyU=";
    };

    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/vercel $out/bin
      cp -r dist $out/lib/vercel/
      makeWrapper ${pkgs.nodejs}/bin/node $out/bin/vercel \
        --add-flags $out/lib/vercel/dist/vc.js
      ln -s vercel $out/bin/vc
      runHook postInstall
    '';

    meta = {
      description = "Vercel CLI";
      homepage = "https://vercel.com";
      mainProgram = "vercel";
    };
  });
in
{
  home.packages = with pkgs; [
    inputs.encore.packages.${pkgs.stdenv.hostPlatform.system}.encore
    cmake
    protobuf
    pulumi
    pulumiPackages.pulumi-go
    unstable.clickhouse
    vercel-cli
    overmind
    docker-compose
    cloudflared
    cue
    google-cloud-sdk
    pgcli
  ];

  programs.encore = {
    enable = true;
    settings = {
      browser = "never";
    };
  };

  programs.fish.shellInit = ''
        # google-cloud-sdk
    	fish_add_path --global --move --path "/opt/homebrew/share/google-cloud-sdk/bin"
        # encore bin folder
    	fish_add_path --global --move --path "$HOME/bin"
  '';

  # work identity, scoped by repo path
  xdg.configFile."jj/conf.d/encore.toml".text = ''
    --when.repositories = ["~/Developer/encoredev"]

    [user]
    email = "nikita@encore.dev"
  '';
}
