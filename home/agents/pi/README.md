# Skill policy

`skill-policy.ts` limits automatic discovery for user-level skills:

- Global: agent-browser, pi-subagents, diagnosing-bugs, tdd, code-review,
  codebase-design, writing-for-agents, encore-service, rex.
- Everything else: explicit `/skill:name` invocation.

Project-local and command-line skills retain their discovery settings. Upstream
explicit-only flags remain respected. Shared skill files are unchanged.

The DuckDuckGo fallback remains in `skills/web-search/search.py`, outside Pi discovery.
