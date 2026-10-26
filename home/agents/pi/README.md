# Model routing

`model-routing.ts` registers `tiered/main`, `tiered/scout`, `tiered/worker`,
`tiered/reviewer`, and `tiered/oracle`. Main sessions and native subagents use
these routes; explicit physical model overrides and external CLI agents bypass them.

| Tier                       | Mixed       | OpenAI-only | Claude-only | Thinking |
| -------------------------- | ----------- | ----------- | ----------- | -------- |
| Main                       | GPT-6.1 Sol | GPT-6.1 Sol | Opus 5.5    | Medium   |
| Scout, researcher          | GPT-6 Luna  | GPT-6 Luna  | Haiku 5.5   | High     |
| Worker, delegate           | GPT-6.1 Sol | GPT-6.1 Sol | Sonnet 5.5  | Medium   |
| Reviewer, evidence auditor | Opus 5.5    | GPT-6.1 Sol | Opus 5.5    | High     |
| Oracle                     | GPT-6 Astra | GPT-6 Astra | Opus 5.5    | Low      |

Thinking levels pass through to the physical model and are clamped by Pi.
`/thinking` and explicit subagent thinking overrides remain available.

Mixed mode excludes a provider after a quota or rate-limit error. All tiered
sessions and children on that machine then use the remaining provider's column.
Each routed request rechecks availability. Normal routing resumes after the
reported ChatGPT retry interval, or after a heuristic cooldown: five minutes
for throttling, one hour for quota exhaustion. These timers are not quota probes.
Missing credentials also select the remaining provider in mixed mode.

Recovery continues the existing session, omitting only the failed response from
model context. Completed tool results remain. A failed response containing tool
calls stops for inspection rather than automatically continuing. Auth, network,
server, and context errors do not trigger provider failover. Both providers being
unavailable stops routing. Direct calls such as compaction use the routes, but
terminal failures outside the agent loop do not get automatic continuation.

Commands:

- `/agent-tier mixed`: automatic cross-provider fallback; default.
- `/agent-tier openai`: restrict every tier to OpenAI; no cross-provider fallback.
- `/agent-tier claude`: restrict every tier to Claude; no cross-provider fallback.
- `/agent-tier status`: show mode and provider cooldowns.
- `/agent-tier reset`: clear cooldowns without changing mode.

Mode and cooldown files live in `~/.pi/agent/model-routing/`, shared across local
sessions and children. Mode commands also select `tiered/main` in the current
session. New sessions select it through settings. Existing physical-model
sessions need `/agent-tier mixed` after `/reload`.

Tests:

```sh
node --experimental-strip-types --test home/agents/pi/model-routing.test.mjs
PI_SDK_ENTRY=/path/to/pi-coding-agent/dist/index.js \
  node --experimental-strip-types --test home/agents/pi/model-routing.integration.test.mjs
```

The SDK integration tests use simulated model responses, with no inference requests.

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
