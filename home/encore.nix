{ inputs, pkgs, ... }:
let
  unstable = import inputs.nixpkgs-unstable { inherit (pkgs.stdenv.hostPlatform) system; };
in
{
  home.packages = with pkgs; [
    inputs.encore.packages.${pkgs.stdenv.hostPlatform.system}.encore
	cmake
	protobuf
    pulumi
    unstable.clickhouse
    vercel-pkg
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
