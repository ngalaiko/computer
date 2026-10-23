{ lib, ... }:
{
  programs.codex = {
    enable = true;
    # hosts that want the CLI installed set their own package
    package = lib.mkDefault null;
    context = ./AGENTS.md;
    # Codex execpolicy counterpart of the Claude Code PreToolUse hooks in
    # ./claude.nix. Rules match command prefixes, so `git` also covers
    # `git push`.
    rules.agents = ''
      prefix_rule(
          pattern = ["git"],
          decision = "forbidden",
          justification = "never use git directly on this machine — use jujutsu (jj) instead (see ~/.codex/AGENTS.md)",
      )

      prefix_rule(
          pattern = ["jj", "git", "push"],
          decision = "forbidden",
          justification = "never push to remote (see ~/.codex/AGENTS.md)",
      )
    '';
  };
}
