{
  description = "Nix-built OCI image for exe.dev machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The Hermes coding agent; keeps its own nixpkgs pin — its uv2nix build is
    # tested against it.
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
      # darwin maps to the matching-arch Linux image so `nix build` works on a
      # Mac (offloaded to the linux-builder VM).
      darwinToLinux = {
        "aarch64-darwin" = "aarch64-linux";
        "x86_64-darwin" = "x86_64-linux";
      };
      allSystems = linuxSystems ++ builtins.attrNames darwinToLinux;
      linuxOf = system: darwinToLinux.${system} or system;

      # The system instance: which services are on and which accounts exist.
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
                  # read by exe.dev at VM creation
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
                    "anthropic" # native Anthropic API to the gateway
                    "mcp" # attach MCP tool servers
                    "computer-use" # computer-use tooling
                    "youtube" # youtube transcript tool
                    "messaging" # telegram (bundles discord+slack too)
                  ];
                  # runtime-PATH tool only (not linked into the venv), so our
                  # nixpkgs' headless build is safe — drops the gtk/pipewire/
                  # gstreamer closure the default ffmpeg drags in
                  ffmpeg = nixpkgs.legacyPackages.${linuxSystem}.ffmpeg-headless;
                };
                settings =
                  # Named providers over the exe.dev LLM integration
                  # (llm.int.exe.xyz — must be attached to the VM, `auto:all`).
                  # Each upstream needs its own wire protocol: anthropic →
                  # /v1/messages, openai → /v1/responses (the gpt-5.x reasoning
                  # models reject tools on chat/completions), fireworks →
                  # chat/completions. openai + fireworks self-populate the picker
                  # via discover_models (hermes GETs <base_url>/models);
                  # anthropic's /models lists nothing, so claude is enumerated by
                  # hand. Every model still needs a model_aliases entry: a bare
                  # known name (claude-*, gpt-*) otherwise resolves to hermes's
                  # built-in provider, not ours. Fireworks ids also carry a
                  # `fireworks/` prefix on the wire.
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
                    # model_aliases pin each short name to its provider (bare id
                    # for claude/gpt, `fireworks/`-prefixed for fireworks).
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
                    # hermes resolves aliases for runtime `-m`/the picker but NOT
                    # for model.default, so resolve the cold-start model here.
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
                        discover_models = false; # integration lists no anthropic models
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
