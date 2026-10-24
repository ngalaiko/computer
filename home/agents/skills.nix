{
  config,
  inputs,
  lib,
  ...
}:
let
  manifest = builtins.fromJSON (
    builtins.readFile "${inputs.mattpocock-skills}/.claude-plugin/plugin.json"
  );
  pluginSkills = builtins.listToAttrs (
    map (path: {
      name = builtins.baseNameOf path;
      value = lib.mkDefault "${inputs.mattpocock-skills}/${lib.removePrefix "./" path}";
    }) manifest.skills
  );
in
{
  options.agents.skills = lib.mkOption {
    type = lib.types.attrsOf lib.types.path;
    default = { };
    description = "Shared skills; harness-specific skills use their own options.";
  };

  config = {
    agents.skills = pluginSkills // {
      rex = ./skills/rex;
    };
    home.file = lib.mapAttrs' (
      name: source: lib.nameValuePair ".agents/skills/${name}" { inherit source; }
    ) config.agents.skills;
    programs.claude-code.skills = config.agents.skills;
  };
}
