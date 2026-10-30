# Feature workflow

Activate `/skill:feature` for a task to use workspace isolation, delegation,
Rex tabs, and Oyo review. Other tasks use the current revision without this flow.
The skill owns these rules; its Oyo and tab procedures are plain references,
not automatically discoverable skills. Apply Home Manager and reload Pi after changes.

# Subagents

`pi.nix` pins stock [`@tintinweb/pi-subagents@0.22.0`](https://github.com/tintinweb/pi-subagents).
No upstream patches or custom RPC bridge are installed.

Home Manager deploys `~/.pi/agent/subagents.json` from `subagents/config.json`
and four `~/.pi/agent/agents/*.md` definitions. Nix renders frontmatter from
`subagents/profiles.json`, then appends shared `home/agents/AGENTS.md` and the
role prompt. Worker and small-worker share `subagents/worker.md`. Replace-mode
prompts exclude parent orchestration instructions and conversation history.

| Role         | Model                    | Effort                                  |
| ------------ | ------------------------ | --------------------------------------- |
| explorer     | openai-codex/gpt-6-luna  | high                                    |
| worker       | openai-codex/gpt-6.1-sol | caller: medium, high for difficult work |
| small-worker | openai-codex/gpt-6-luna  | high                                    |
| reviewer     | claude-code-cli/opus     | high                                    |

Worker deliberately omits `thinking` frontmatter: upstream pins are authoritative,
so a medium pin would prevent a caller requesting high. Always pass worker
`thinking` explicitly. Ambiguous small-worker tasks go to worker. Explorer and
reviewer have only `read, grep, find, ls`; the parent runs review tests. Workers
have the seven built-in coding tools. All four allow only the absolute command-guards
extension path and inherit skills, not the parent's full extension set.
Upstream allowlists filter extension registration; discovered extension factories
may still execute during loading. Guards and allowlists are not an OS sandbox. Nested delegation is disabled by both depth and
agent allowlists. Default agents, fallback dispatch, package agents/workflows,
scheduling, scripted workflows, and Git worktree isolation are disabled.
Project-local definitions and `.pi/subagents.json` can override these global defaults.

Before use, check `/agents → Agent types` for model availability, especially
`claude-code-cli/opus`; Claude Code must be installed and signed in. Upstream
resolves model pins tolerantly, including other providers, and can inherit the
parent model when a pin is unavailable. Pins are not fail-closed model enforcement.
Thinking can be clamped to the model's supported levels; `showModel` displays the
actual model/effort in the widget. Widget mode is `all`; FleetView is enabled.

## Dispatch and completion

Use a self-contained task; children execute and return a final answer without a
confirmation handshake. Resolve material questions before dispatch. For example:

```js
Agent({
  subagent_type: "worker",
  name: "settings-migration",
  description: "Migrate settings and tests",
  thinking: "medium",
  run_in_background: true,
  prompt:
    "Implement <goal> in /absolute/jj/workspace. Scope: <files>. Constraints: <rules>. Use absolute file paths and cd /absolute/jj/workspace && for shell commands; your cwd remains the parent's. Run <tests>. Stop at <acceptance criteria>. Return changed files, test results, and blockers.",
});
```

Continue independent work, then yield for the background completion notification.
Use `get_subagent_result({agent_id: "<id>"})` for full output, not repeated polling.
`steer_subagent({agent_id: "<id>", message: "<correction>"})` redirects a running
agent. `Agent({resume: "<id>", ...})` continues a completed conversation; use a
fresh reviewer instead for each independent review. Supply requirements, paths,
and `jj diff`, not implementation reasoning or another agent's history.

`maxConcurrent: 2` and `maxConcurrentForeground: 2` bound **separate** pools,
not a combined total. Foreground resume bypasses its pool, and handing foreground
work to the background can exceed the background cap. The parent must maintain
a combined two-active-child policy. Prefer background dispatch throughout.
Finished runs do not require actor-style slot cleanup. `/agents` and FleetView
inspect live conversations; persisted upstream sessions can be resumed.

## JJ workspaces

For explicitly activated feature tasks, create each implementation writer's
workspace from `writer_base`, the recorded full approved commit ID verified against
the persistent task bookmark (or the initial intended task base), not mutable `@`:

```sh
cd "$task_workspace" && jj --config git.colocate=false workspace add --name <unique-name> -r "$writer_base" <absolute-path>
```

Keep workspaces under `~/.pi/agent/jj-workspaces/` and preserve package-relative
subdirectories. Ignored files, dependencies, and secrets are not copied.
`Agent` has **no per-invocation cwd parameter**: the child retains the parent's cwd.
Require absolute paths and explicit shell `cd` into the supplied workspace.
This is prompt-only workspace discipline, not runtime isolation. Read-only tool
scoping also does not restrict which paths can be read.

Upstream cross-extension RPC supports a real `options.cwd` for tools, while still
loading the parent's project configuration. That API is not exposed by the standard
`Agent` tool and is not wired here. Built-in Git worktrees are disabled to avoid
Git commands and automatic commits. Integration requires explicit operator
approval. Disposable child cleanup follows verified approved integration and
ownership/process gates; task and coordinator teardown also require explicit
completion. See `skills/feature/finishing.md`.

## Apply and test

Apply Home Manager, then restart Pi. Activation replaces the managed package list
and removes the obsolete inline `settings.json` subagents block while retaining
other settings. Home Manager removes obsolete actor-managed settings/roles files.
Old actor sessions are not migrated; existing untracked files are not deleted.

Network-free checks:

```sh
node --experimental-strip-types --test home/agents/pi/{subagents,skill-policy,command-guards}.test.mjs
```

Optional parser integration uses a read-only upstream checkout or unpacked npm
package, plus the host's existing jiti loader; it does not edit installed packages:

```sh
PI_SUBAGENTS_DIR=/absolute/path/to/pi-subagents \
PI_JITI_MODULE=/absolute/path/to/jiti/lib/jiti.mjs \
PI_CODING_AGENT_MODULE=/absolute/path/to/pi-coding-agent/dist/index.js \
node --test home/agents/pi/subagents.test.mjs
```

This checks rendered definitions through public `loadCustomAgents` and settings
through `loadSettings`, without model requests. `PI_SUBAGENTS_DEPLOYMENT` can
point to evaluated Home Manager JSON shaped as `{settings: "<JSON>", agents:
{explorer: "<Markdown>", ...}}` to verify actual Nix rendering as well.

Schema references: upstream [agent fields and tools](https://github.com/tintinweb/pi-subagents#frontmatter-fields),
[persistent settings](https://github.com/tintinweb/pi-subagents#persistent-settings),
and [RPC cwd](https://github.com/tintinweb/pi-subagents/blob/master/docs/rpc.md).

# Oyo feedback

Home Manager deploys the first-party `oyo-review/` extension directory to parents;
children retain command guards only. Delivery is inactive until deployed, Pi
reloaded, and `oyo_watch` explicitly started after verifying the native Oyo UI.
Supply its exact native session name, absolute workspace and trusted absolute
`oyBin` (optional absolute `jjBin`). Read the initial tool result before claiming
it active. It returns saved human-or-untyped comments and active/outdated root
counts without also sending an initial notification.

Saved additions, body edits, deletions and root resolve/reopen changes wake the
owning Pi via visible follow-up messages. No agent-to-human notification UI,
publication, reply writes or automatic resolution. Replies use the native CLI
with explicit agent identity per `oyo-review`. Only local feedback qualifies:
provider-backed comment bodies are filtered even without authorType; roots/status
still count with unknown actors. Agent/bot bodies and metadata-only
changes do not echo. Missing authorType is not authenticated human provenance;
status/deletion actors are unknown. Status-only events authorize no reply or
integration.

Polling runs about one second after the previous poll completes, plus CLI latency.
Snapshots coalesce intermediate edits/toggles; comments created and deleted
entirely between polls are unobservable. This is not an exact hook/event journal.
No-loss retry covers validated observed snapshots only. Delivery failures retain
that batch until acceptance; three consecutive CLI/delivery failures stop the
watcher. The pinned identity is workspace, session, PID, socket, JJ change ID and
review key; native name, workspace and target are validated on every snapshot.
Oyo's `createdAt` is validated but not pinned because it changes on target reload.
Identity replacement stops immediately. Each CLI call has a five-second
limit and 4 MiB output bound; snapshots allow 2,000 comments, 64 KiB bodies and
128 KiB delivery batches. Oversized or malformed data fails explicitly, without
truncation or false deletion. Whole-file anchor blobs are discarded.

Use `oyo_watch` actions `status` and `stop` to inspect or end delivery. Unavailable
counts are unknown, not zero. `stoppedReason` distinguishes explicit/lifecycle
stops from errors. Stop and verify stopped before integration rebase/source
movement, closing Oyo or workspace cleanup. Actual session_tree and session_shutdown
(including reload) abort pending work and fence late callbacks; canceled before-tree
navigation does not stop delivery. Shutdown emits no automatic notification/turn. Nothing auto-resumes; explicit restart returns native durable comments
as a fresh baseline. See the first-party skill for identity checks, native reply
limitations and cleanup gates. Invalid basic start input preserves an existing
watch; snapshot/native-identity failure after deliberate replacement leaves the
previous watch unavailable.

The bridge uses only read commands, but Oyo may reconcile persisted anchors/author metadata
during reads. The bridge performs no comment/post/resolve writes.

```sh
node --experimental-strip-types --test home/agents/pi/oyo-review.test.mjs
```

# Feature finishing

`skills/feature/finishing.md` owns integration, history and cleanup gates;
`oyo-review.md` owns isolation and human review. `/skill:feature` stays the entry
point. Finishing executors receive exact approved resources, current identity
pins, allowed commands and expected results. The parent retains approval,
ownership decisions, process checks and final verification.

Use `worker` for integration judgment. Trial `small-worker` only for resolved,
conflict-free mechanics. Run the read-only `scripts/finishing-check.mjs` preflight
before mutations; it neither authorizes nor performs cleanup. Record total cost,
time, retries and parent corrections in `~/.pi/agent/finishing-trials/`; retain
trial records across task cleanup.

```sh
node --test home/agents/pi/finishing-{check,workflow}.test.mjs
```

# Skill policy

`feature` is explicit-only. `skill-policy.ts` advertises coding skills, Encore, Rex, and `pi-subagents` guidance
if discovered. The subagent extension's tools are registered independently of skill
advertising; this package currently ships no skills. Other user skills require
explicit invocation. Project-local, command-line, and upstream explicit-only flags
remain unchanged.
