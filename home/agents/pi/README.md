# Rex inspector

`rex-inspector.ts` connects Fleet's Enter/H actions to a split beside Pi's Rex
pane. Focus stays on Pi unless explicitly requested. Inspector commands run
directly, preserving their arguments and permissions.

This integration is open-only: close panes through Rex. Closing an inspector
does not stop its subagent.

# Skill policy

`skill-policy.ts` limits automatic discovery for user-level skills:

- Global: agent-browser, pi-subagents, diagnosing-bugs, tdd, code-review,
  codebase-design, writing-for-agents, encore-service, rex.
- Everything else: explicit `/skill:name` invocation.

Project-local and command-line skills retain their discovery settings. Upstream
explicit-only flags remain respected. Shared skill files are unchanged.

The DuckDuckGo fallback remains in `skills/web-search/search.py`, outside Pi discovery.
