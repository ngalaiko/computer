{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agents.pi;
  subagentSettings = builtins.fromJSON (builtins.readFile ./pi/subagents/config.json);
  subagentProfiles = builtins.fromJSON (builtins.readFile ./pi/subagents/profiles.json);
  subagentFiles = lib.mapAttrs' (
    name: profile:
    let
      frontmatter = profile // {
        inherit name;
        extensions = [ "${config.home.homeDirectory}/.pi/agent/extensions/command-guards.ts" ];
        skills = true;
        allowed_subagents = false;
        prompt_mode = "replace";
        inherit_context = false;
        isolation = "off";
      };
    in
    lib.nameValuePair ".pi/agent/agents/${name}.md" {
      text =
        "---\n"
        + lib.concatStringsSep "\n" (
          lib.mapAttrsToList (key: value: "${key}: ${builtins.toJSON value}") frontmatter
        )
        + "\n---\n\n"
        + builtins.readFile ./AGENTS.md
        + "\n"
        + builtins.readFile (
          if name == "small-worker" then ./pi/subagents/worker.md else ./pi/subagents + "/${name}.md"
        );
    }
  ) subagentProfiles;
  settings = pkgs.writeText "pi-settings.json" (
    builtins.toJSON {
      defaultProvider = "openai-codex";
      defaultModel = "gpt-6.1-sol";
      defaultThinkingLevel = "medium";
      theme = "zenwritten";
      quietStartup = true;
      hideThinkingBlock = true;
      showHardwareCursor = true;
      collapseChangelog = true;
      packages = [
        "npm:@tintinweb/pi-subagents@0.22.0"
        "npm:pi-web-access@0.44.0"
        "npm:claude-code-pi@1.2.1"
      ];
      skills = [ ];
    }
  );
in
{
  options.agents.pi = {
    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Pi skills keyed by directory name.";
    };
    mcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Pi MCP servers.";
    };
  };

  config.home.file = {
    ".pi/agent/AGENTS.md".text = builtins.readFile ./AGENTS.md + builtins.readFile ./pi/AGENTS.md;
    ".pi/agent/themes/zenwritten.json".source = ./pi/themes/zenwritten.json;
    ".pi/agent/extensions/command-guards.ts".source = ./pi/command-guards.ts;
    ".pi/agent/extensions/jj-footer.ts".source = ./pi/jj-footer.ts;
    ".pi/agent/extensions/skill-policy.ts".source = ./pi/skill-policy.ts;
    ".pi/agent/subagents.json".text = builtins.toJSON subagentSettings;
    ".pi/agent/mcp.json".text = builtins.toJSON { inherit (cfg) mcpServers; };
  }
  // subagentFiles
  // lib.mapAttrs' (
    name: source: lib.nameValuePair ".pi/agent/skills/${name}" { inherit source; }
  ) cfg.skills;

  config.agents.pi.skills = {
    feature-tabs = ./pi/skills/feature-tabs;
    oyo-review = ./pi/skills/oyo-review;
  }
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    agent-browser = ./pi/skills/agent-browser;
  };

  config.home.activation.piSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.python3}/bin/python3 ${./pi/settings.py} \
      ${lib.escapeShellArg "${config.home.homeDirectory}/.pi/agent/settings.json"} ${settings}
  '';
}
