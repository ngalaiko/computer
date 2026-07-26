{ pkgs, inputs, ... }:
let
  # open-webui from unstable for the newer release (25.11 stops at 0.8.x). Its
  # license (BSD-3 plus a branding clause since 0.6.6) is marked unfree, so
  # allow just it.
  unfree = import ../../../packages/unstable.nix {
    inherit inputs pkgs;
    allowUnfree = [ "open-webui" ];
  };
in
{
  services.open-webui = {
    enable = true;
    # Strip the local-inference stack (~1.8 GB: torch, sentence-transformers,
    # transformers, accelerate, faster-whisper, opencv, rapidocr, datasets, and
    # the triton/scipy/sympy/gcc they drag in). Every one is lazy-imported and
    # gated behind a config engine, so RAG/STT/reranking just have to run against
    # external providers instead of local models. chromadb stays: it's the
    # default VECTOR_DB and is instantiated at boot (retrieval/vector/factory.py).
    # Requires the *_ENGINE settings below so nothing tries to load a local model.
    #
    # Drop them from both the propagated inputs (so they leave the closure) and
    # the wheel's Requires-Dist metadata (pythonRemoveDeps), else nixpkgs'
    # pythonRuntimeDepsCheckHook fails the build for the now-missing dists.
    package =
      let
        drop = [
          "accelerate"
          "sentence-transformers"
          "transformers"
          "faster-whisper"
          "rapidocr-onnxruntime"
          "opencv-python-headless"
          "datasets"
          "einops"
          "sentencepiece"
        ];
      in
      unfree.open-webui.overridePythonAttrs (old: {
        dependencies = builtins.filter (p: !builtins.elem (pkgs.lib.getName p) drop) old.dependencies;
        pythonRemoveDeps = (old.pythonRemoveDeps or [ ]) ++ drop;
      });
    # Override replaces the option default (the telemetry opt-outs), so restate
    # them, then force every ML feature onto an external engine — the local
    # models were just removed from the closure.
    environment = {
      SCARF_NO_ANALYTICS = "true";
      DO_NOT_TRACK = "true";
      ANONYMIZED_TELEMETRY = "false";
      # embeddings via the OpenAI API instead of local SentenceTransformers.
      RAG_EMBEDDING_ENGINE = "openai";
      # speech-to-text via an OpenAI-compatible API instead of local Whisper.
      AUDIO_STT_ENGINE = "openai";
    };
  };

  # pydub (open-webui audio: STT/TTS transcoding) shells out to ffmpeg/ffprobe
  # and warns at startup without it; headless = no X/GUI closure, and it's
  # already in the image via the cptr account so it adds nothing.
  users.users.open-webui.packages = [ pkgs.ffmpeg-headless ];

  services.backup = {
    enable = true;
    # accounts db + uploads + vector db + the JWT secret key all live here.
    paths = [ "/var/lib/open-webui" ];
  };
}
