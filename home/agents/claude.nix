{ config, ... }:
let
  # Claude Code PreToolUse hooks enforcing the AGENTS.md rules on every Bash
  # command. Each greps the command and hard-denies before it runs. Patterns
  # anchor to command position ((^|separator) then optional spaces) so a token
  # only matches when it is actually the command being run, not a substring —
  # e.g. "never use git" deliberately ignores `jj git push`, which is covered
  # by its own hook below.
  gitFlags = "(-[^[:space:]]+[[:space:]]+([^-][^[:space:]]*[[:space:]]+)?)*";
  sep = "(^|[;&|(`])[[:space:]]*";

  denyHook =
    pattern: reason:
    ''cmd=$(jq -r '.tool_input.command // ""'); if printf '%s' "$cmd" | grep -Eq '${pattern}'; then printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"${reason}"}}'; fi'';

  # never use git directly — steer to jujutsu
  neverGitHook = denyHook "${sep}git([[:space:]]|$)" "Blocked by no-git hook: never use git directly on this machine — use jujutsu (jj) instead (see ~/.config/AGENTS.md).";

  # block a direct `git push`
  gitPushHook = denyHook "${sep}git[[:space:]]+${gitFlags}push($|[[:space:]])" "Blocked by no-push hook: never push to remote (see ~/.config/AGENTS.md). Do not run git push.";

  # block pushing via jujutsu's git backend: `jj git push`
  jjGitPushHook = denyHook "${sep}jj[[:space:]]+${gitFlags}git[[:space:]]+${gitFlags}push($|[[:space:]])" "Blocked by no-push hook: never push to remote (see ~/.config/AGENTS.md). Do not run jj git push.";

  bashHook = command: statusMessage: {
    inherit command statusMessage;
    type = "command";
  };
in
{
  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/AGENTS.md";

  home.file.".claude/settings.json".text = builtins.toJSON {
    theme = "auto";
    enabledPlugins = {
      "mattpocock-skills@claude-plugins-official" = true;
    };
    hooks.PreToolUse = [
      {
        matcher = "Bash";
        hooks = [
          (bashHook neverGitHook "Checking for git usage")
          (bashHook gitPushHook "Checking for git push")
          (bashHook jjGitPushHook "Checking for jj git push")
        ];
      }
    ];
  };
}
