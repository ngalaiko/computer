{ pkgs, inputs, ... }:
let
  # open-webui moves fast; pin to unstable for a fresher build (cf. claude-code
  # on the mac). Its "Open WebUI License" is unfree, so allow just that package.
  unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfreePredicate = p: pkgs.lib.getName p == "open-webui";
  };
in
{
  services.open-webui = {
    enable = true;
    package = unstable.open-webui;
    environment = {
      # exe.dev LLM gateway. Open WebUI speaks OpenAI-compatible
      # /chat/completions; the fireworks endpoint serves it (the openai one is
      # /v1/responses-only). Models: deepseek/kimi/glm/qwen/gpt-oss.
      OPENAI_API_BASE_URL = "https://llm.int.exe.xyz/fireworks/inference/v1";
      OPENAI_API_KEY = "irrelevant"; # gateway ignores it, but the field is required.
      # not using Ollama; skip its (failing) probe.
      ENABLE_OLLAMA_API = "False";
      # Multi-user: Open WebUI's own login is on (WEBUI_AUTH defaults to True).
      # New registrations land as 'admin' (not the default 'pending', which
      # blocks a user until approved) so whoever signs up can manage the
      # instance. Access is already gated by exe.dev auth. Note the first
      # registrant is admin regardless; this makes later ones admin too.
      # DEFAULT_USER_ROLE is a PersistentConfig — seeds a fresh DB only; flip it
      # to 'user' via Admin Panel → Settings once your account exists.
      DEFAULT_USER_ROLE = "admin";
    };
  };

  services.backup = {
    enable = true;
    # DATA_DIR (webui.db, uploads, vector store, secret key) lives here.
    paths = [ "/var/lib/open-webui" ];
  };
}
