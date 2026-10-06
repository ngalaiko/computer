# encore work setup: darwin-level homebrew plus the home-manager config.
{ ... }:
{
  homebrew = {
    taps = [
      "hamed-elfayome/claude-usage"
    ];

    brews = [
      "vercel" # not in nixpkgs (nodePackages removed); npm tarball needs its own deps
    ];

    casks = [
      "1password"
      "claude" # Anthropic's Claude desktop app; hosts the Claude Code desktop experience
      "discord"
      "linear"
      "notion"
      "paper-design" # paper.design canvas design tool
      "slack"
      "hamed-elfayome/claude-usage/claude-usage-tracker"
    ];
  };

  home-manager.users."nikita" =
    {
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      unstable = import inputs.nixpkgs-unstable { inherit (pkgs.stdenv.hostPlatform) system; };
      # shared skills from encoredev/agents-setup; sync-skills is replaced by
      # `nix flake update encore-agents-setup`.
      agentSkills = lib.mapAttrs (name: _: "${inputs.encore-agents-setup}/skills/${name}") (
        lib.filterAttrs (name: type: type == "directory" && name != "sync-skills") (
          builtins.readDir "${inputs.encore-agents-setup}/skills"
        )
      );
    in
    {
      imports = [ inputs.encore.homeModules.default ];

      home.packages = with pkgs; [
        inputs.encore.packages.${pkgs.stdenv.hostPlatform.system}.encore
        cmake
        protobuf
        pulumi
        pulumiPackages.pulumi-go
        unstable.clickhouse
        overmind
        docker-compose
        cloudflared
        cue
        (google-cloud-sdk.withExtraComponents [ google-cloud-sdk.components.bigtable ])
        pgcli
        pnpm
        stripe-cli
        inputs.dash0-cli.packages.${pkgs.stdenv.hostPlatform.system}.dash0
      ];

      programs.claude-code = {
        mcpServers.plain = {
          type = "http";
          url = "https://mcp.plain.com/mcp";
        };
        settings.enabledPlugins."dash0@claude-plugins-official" = true;
        skills = agentSkills;
      };

      home.file = lib.mapAttrs' (
        name: src: lib.nameValuePair ".codex/skills/${name}" { source = src; }
      ) agentSkills;

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

      programs.fish.functions.pgprod = {
        argumentNames = [ "db" ];
        body = ''
          set -l socket "/tmp/ssh-pg-$db.sock"
          set -l remote "ubuntu@platform-prod-a1"

          echo "Opening tunnel..."
          ssh -fN -M -S "$socket" -L 5433:localhost:5432 "$remote"

          echo "Connecting to DB..."
          env PGPASSWORD=(gcloud secrets versions access latest --secret="DatabasePassword_admin" --project=encore-prod-secrets) \
            pgcli -h localhost -p 5433 -U platform-admin "$db" -d platform \
            --prompt (printf '\x1b[31mprod-platform>\x1b[0m ')

          echo "Closing tunnel..."
          ssh -S "$socket" -O exit "$remote"
        '';
      };

      # work identity, scoped by repo path
      xdg.configFile."jj/conf.d/encore.toml".text = ''
        --when.repositories = ["~/Developer/encoredev"]

        [user]
        email = "nikita@encore.dev"
      '';
    };
}
