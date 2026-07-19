{
  pkgs,
  lib,
  inputs,
  ...
}:
{
  services.hermes = {
    enable = true;
    package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.minimal.override {
      extraDependencyGroups = [
        "anthropic"
        "mcp"
        "computer-use"
        "youtube"
        "messaging"
        "edge-tts"
      ];
      # headless: drops the gtk/pipewire/gstreamer closure.
      ffmpeg = pkgs.ffmpeg-headless;
    };
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

  users.users.hermes = {
    packages = with pkgs; [
      gh
      git
      himalaya
      jq
      chromium
      (import ../../../packages/agent-browser { inherit pkgs; })
      (import ../../../packages/blogwatcher-cli { inherit pkgs; })
    ];
    environment = {
      # agent-browser uses this instead of downloading its own chromium.
      AGENT_BROWSER_EXECUTABLE_PATH = lib.getExe pkgs.chromium;
      # for exedev github integration
      GH_HOST = "computer.int.exe.xyz";
    };
  };

  services.backup = {
    enable = true;
    paths = [ "/var/lib/hermes" ];
  };

  # /hermes/* on the public port. Caddyfile under /var/lib/hermes is backed up.
  services.ingress.tenants.hermes = {
    upstreamPort = 8081;
    routes = ''
      # edit, then: caddy reload --config ~/.caddy/Caddyfile
      reverse_proxy 127.0.0.1:8644
    '';
  };
}
