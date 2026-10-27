# Delegation

Main sessions use Sol at medium effort. `delegate.ts` adds one tool:

| Role               | Model           | Effort | Access                            |
| ------------------ | --------------- | ------ | --------------------------------- |
| `worker` (default) | GPT-6.1 Sol     | Medium | Isolated JJ workspace             |
| `small-worker`     | GPT-6.1 Terra   | Medium | Isolated JJ workspace             |
| `reviewer`         | Claude CLI Opus | High   | Read-only tools, no new workspace |

Main decides when to delegate without asking: independent implementation to
`worker`, bounded changes to `small-worker`, and substantive review to `reviewer`.
It works directly when delegation adds overhead. Each task includes requirements,
relevant paths, and acceptance criteria. Workspace creation and child sessions are
automatic. You can also request delegation explicitly.

```json
{ "task": "Add input validation and tests in the API service." }
```

Review retained work with its returned workspace path:

```json
{
  "role": "reviewer",
  "cwd": "/returned/workspace",
  "task": "Review API input validation against these requirements: ..."
}
```

Writers start on top of the source working-copy change, including its snapshotted
files. A source subdirectory maps to the same subdirectory in the new workspace.
Untracked ignored files, dependencies, and local secrets are not copied; workers
may need to install dependencies. Reviewers receive the current-change diff and
can inspect source files, but cannot run tests.

The tool waits for completion. Two delegates may run concurrently per parent
session. There is no background scheduler, nested delegation, provider fallback,
or automatic integration. Parent cancellation and session shutdown terminate
child process groups. Process-group cancellation requires macOS or Linux.

Results, prompts, sessions, and writer workspaces remain under
`~/.pi/agent/delegations/`, including after failure or cancellation. Nothing is
automatically merged or deleted. Ask Pi to inspect and integrate a returned JJ
change, or remove its workspace, only when ready. Integration and deletion require
explicit approval. Retained artifacts can contain private source and prompts.

Children start with fresh context. Writers load only command-guards; reviewers
also load `claude-code-pi@1.2.1` and use `claude-code-cli/opus` through local
`claude -p`. Claude Code must be installed and signed in with your subscription.
The bridge has no API fallback and starts a process per model turn. Pi executes
read-only review tools; Claude Code tools and MCP are disabled by the bridge.
MCP and ambient Pi extensions are disabled. Parent project trust carries only to its
source workspace and trusted workspaces created in that session. Read-only tool
selection and nested-delegation guards are workflow controls, not a sandbox.

Tests use real temporary JJ repositories and a simulated Pi subprocess:

```sh
node --experimental-strip-types --test home/agents/pi/delegate.test.mjs
```

Set `PI_SDK_ENTRY` to Pi's `dist/index.js` to include validated SDK tool dispatch.
No inference requests are made.

Apply the Home Manager configuration and restart Pi to replace the old subagent
package and routing extensions. Existing sessions may restore their recorded
`tiered/*` selection; select `openai-codex/gpt-6.1-sol` with `/model` or start a new
session. Old routing state and plugin artifacts are left untouched.

# Skill policy

`skill-policy.ts` limits automatic user-level skill discovery to agent-browser,
diagnosing-bugs, tdd, code-review, codebase-design, writing-for-agents,
encore-service, and rex. Other user skills require explicit invocation.
Project-local and command-line discovery, and upstream explicit-only flags,
remain unchanged.
