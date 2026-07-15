{
  description = "Nix-built OCI image for exe.dev machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # own nixpkgs pin (no follows): its uv2nix build is tied to it.
    hermes-agent.url = "github:NousResearch/hermes-agent";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      hermes-agent,
    }:
    let
      lib = nixpkgs.lib;

      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      # darwin builds the matching-arch Linux image via the linux-builder VM.
      darwinToLinux = {
        "aarch64-darwin" = "aarch64-linux";
        "x86_64-darwin" = "x86_64-linux";
      };
      allSystems = linuxSystems ++ builtins.attrNames darwinToLinux;
      linuxOf = system: darwinToLinux.${system} or system;

      exedevFor =
        linuxSystem:
        let
          exedev = import ./modules/exedev { pkgs = nixpkgs.legacyPackages.${linuxSystem}; };
          system = exedev.eval (
            { pkgs, ... }:
            {
              image = {
                name = "computer.exe";
                workingDir = "/home/exedev";
                labels = {
                  "org.opencontainers.image.title" = "computer.exe";
                  "org.opencontainers.image.description" = "exe.dev image: s6-overlay, OpenSSH, and Hermes";
                  "exe.dev/login-user" = "exedev";
                };
                packages = with pkgs; [
                  bashInteractive
                  coreutils-full
                  findutils
                  gnugrep
                  gnused
                  iproute2
                  procps
                  tzdata
                  util-linux
                  curl
                  git
                  jq
                  chromium
                  (import ./packages/agent-browser { inherit pkgs; })
				  gh
                ];
              };

              services.sshd = {
                enable = true;
                authorizedKeys.user = "exedev";
              };
              services.hermes = {
                enable = true;
                package = hermes-agent.packages.${linuxSystem}.minimal.override {
                  extraDependencyGroups = [
                    "anthropic"
                    "mcp"
                    "computer-use"
                    "youtube"
                    "messaging"
                    "edge-tts"
                  ];
                  # headless: drops the gtk/pipewire/gstreamer closure.
                  ffmpeg = nixpkgs.legacyPackages.${linuxSystem}.ffmpeg-headless;
                };
                # agent-browser uses this instead of downloading its own chromium.
                environment.AGENT_BROWSER_EXECUTABLE_PATH = "/bin/chromium";
                ports = [ 8644 ];
                # exe.dev LLM integration (llm.int.exe.xyz, attached auto:all).
                settings =
                  let
                    base = "https://llm.int.exe.xyz";
                    claudeModels = [
                      "claude-opus-4-8"
                      "claude-fable-5"
                      "claude-opus-4-7"
                      "claude-opus-4-6"
                      "claude-sonnet-5"
                      "claude-sonnet-4-6"
                      "claude-haiku-4-5"
                    ];
                    gptModels = [
                      "gpt-5.6-sol"
                      "gpt-5.6-terra"
                      "gpt-5.6-luna"
                      "gpt-5.5"
                      "gpt-5.5-pro"
                      "gpt-5.4"
                      "gpt-5.4-mini"
                      "gpt-5.3-codex"
                      "gpt-5-codex"
                    ];
                    fireworksShort = [
                      "glm-5p2"
                      "kimi-k2p7-code"
                      "kimi-k2p6"
                      "deepseek-v4-pro"
                      "deepseek-v4-flash"
                      "minimax-m3"
                      "qwen3p7-plus"
                      "gpt-oss-120b"
                    ];
                    fireworksId = m: "fireworks/${m}";
                    # a bare known model name resolves to hermes's built-in
                    # provider unless an alias pins it to ours.
                    aliasList =
                      provider: toId: names:
                      map (m: {
                        name = m;
                        value = {
                          model = toId m;
                          inherit provider;
                        };
                      }) names;
                    aliases = lib.listToAttrs (
                      aliasList "exe-anthropic" (m: m) claudeModels
                      ++ aliasList "exe-openai" (m: m) gptModels
                      ++ aliasList "exe-fireworks" fireworksId fireworksShort
                    );
                    # aliases aren't resolved for model.default; resolve here.
                    defaultModel = "deepseek-v4-flash";
                  in
                  {
                    model = {
                      default = aliases.${defaultModel}.model;
                      provider = aliases.${defaultModel}.provider;
                    };
                    providers = {
                      exe-anthropic = {
                        base_url = "${base}/anthropic";
                        api_mode = "anthropic_messages";
                        api_key = "irrelevant";
                        discover_models = false; # /models lists no anthropic
                        default_model = "claude-opus-4-6";
                        models = claudeModels;
                      };
                      exe-openai = {
                        base_url = "${base}/openai/v1";
                        api_mode = "codex_responses"; # /v1/responses
                        api_key = "irrelevant";
                        discover_models = true;
                      };
                      exe-fireworks = {
                        base_url = "${base}/fireworks/inference/v1";
                        api_mode = "chat_completions";
                        api_key = "irrelevant";
                        discover_models = true;
                        default_model = fireworksId "deepseek-v4-flash";
                      };
                    };
                    model_aliases = aliases;
                  };
              };

              services.backup = {
                enable = true;
                paths = [ "/var/lib/hermes" ];
              };

              users.users.exedev = {
                uid = 1000;
                group = "exedev";
                home = "/home/exedev";
                createHome = true;
                shell = "/bin/sh";
                description = "exe.dev user";
              };
              users.groups.exedev.gid = 1000;

              environment.etc.motd.text = ''
                exe.dev image

                This image is built by Nix and includes a PTY-capable login
                environment, OpenSSH, and the Hermes agent.
              '';
            }
          );
        in
        system.build.image;

      releaseFor = system: import ./packages/release { pkgs = nixpkgs.legacyPackages.${system}; };
    in
    {
      # This Mac, configured with a Linux builder VM (so it can build *-linux).
      darwinConfigurations.mac = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit inputs; };
        modules = [ ./hosts/mac ];
      };

      # `nix build .#exedev` (current system) or `.#packages.<sys>.exedev`.
      packages = lib.genAttrs allSystems (
        system:
        let
          img = exedevFor (linuxOf system);
        in
        {
          exedev = img;
          default = img;
        }
        // releaseFor system
      );

      devShells = lib.genAttrs allSystems (system: {
        default =
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in
          pkgs.mkShell {
            packages = [
              pkgs.gh
              pkgs.gitMinimal
              pkgs.regctl
              pkgs.jujutsu
              pkgs.skopeo
            ]
            ++ lib.attrValues (releaseFor system);
          };
      });

      formatter = lib.genAttrs allSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
