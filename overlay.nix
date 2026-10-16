# Repo packages, plus `pkgs.unstable`: one nixpkgs-unstable instance that shares
# the host's nixpkgs config (unfree allowances included).
{ inputs }:
final: prev: {
  unstable = import inputs.nixpkgs-unstable {
    inherit (final.stdenv.hostPlatform) system;
    inherit (prev) config;
  };

  obsidian-headless = final.callPackage ./packages/obsidian-headless { };
  transcripted = final.callPackage ./packages/transcripted { };
  vault-sync = final.callPackage ./packages/vault-sync { };
  wherenow = final.callPackage ./packages/wherenow { };
}
