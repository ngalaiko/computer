{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agents.pi;
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
        "npm:pi-subagents@0.82.1"
        "npm:pi-web-access@0.44.0"
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
    ".pi/agent/AGENTS.md".source = ./AGENTS.md;
    ".pi/agent/themes/zenwritten.json".source = ./pi/themes/zenwritten.json;
    ".pi/agent/extensions/command-guards.ts".source = ./pi/command-guards.ts;
    ".pi/agent/extensions/jj-footer.ts".source = ./pi/jj-footer.ts;
    ".pi/agent/extensions/skill-policy.ts".source = ./pi/skill-policy.ts;
    ".pi/agent/extensions/rex-inspector.ts".source = ./pi/rex-inspector.ts;
    ".pi/agent/mcp.json".text = builtins.toJSON { inherit (cfg) mcpServers; };
  }
  // lib.mapAttrs' (
    name: source: lib.nameValuePair ".pi/agent/skills/${name}" { inherit source; }
  ) cfg.skills;

  config.agents.pi.skills = lib.optionalAttrs pkgs.stdenv.isDarwin {
    agent-browser = ./pi/skills/agent-browser;
  };

  config.home.activation.piSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.python3}/bin/python3 ${./pi/settings.py} \
      ${lib.escapeShellArg "${config.home.homeDirectory}/.pi/agent/settings.json"} ${settings}
  '';
}
