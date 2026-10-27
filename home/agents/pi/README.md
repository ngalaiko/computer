# Subagents

`pi.nix` installs `pi-subagents@0.82.1` with three custom agents:

| Agent          | Model           | Effort | Tools                    |
| -------------- | --------------- | ------ | ------------------------ |
| `worker`       | GPT-6.1 Sol     | Medium | Read, shell, edit, write |
| `small-worker` | GPT-6.1 Terra   | Medium | Read, shell, edit, write |
| `reviewer`     | Claude CLI Opus | High   | Read, grep, find, ls     |

Definitions live in `subagents/*.md`; runtime settings in `subagents/config.json`.
Builtins are disabled. Project agents can still override user definitions.
Home Manager owns the `subagents` settings block; activation replaces runtime
changes made by model-profile or agent-management commands.

Runs start asynchronously with fresh context. The parent continues independent
work and receives completion notifications. Two top-level async runs may be active;
workflow concurrency is also two. Nested delegation is disabled for these agents.
Automatic workflow revival is disabled; resume interrupted work explicitly.

## Visibility and control

- FleetView shows live activity below the editor.
- `/subagents-fleet` opens transcripts and tool output; `s` steers, `D` stops.
- `/subagents-stop` selects background runs to stop.
- `/subagents-models` shows effective role mappings.
- `/subagent-cost` includes async child usage, unlike Pi's session footer.

Background children survive parent-turn cancellation and may outlive Pi. Use the
upstream stop controls to terminate them. Artifacts and retention follow upstream
policy; retain important evidence separately.

## JJ isolation

The Pi-only parent instructions in `AGENTS.md` require a separate JJ workspace per
writer. This is instruction-based, not an enforced isolation boundary. Upstream's
managed worktrees use Git, so `worktree` stays false. There is no custom runner or
workspace adapter.

The parent creates a unique workspace from the source working-copy change, then
launches the writer with its absolute path:

```json
{
  "agent": "worker",
  "task": "Add input validation and focused tests. Report changed files and results.",
  "cwd": "/absolute/path/to/jj/workspace",
  "async": true,
  "worktree": false
}
```

Preserve the source-relative subdirectory for package-scoped tasks. Ignored files,
dependencies, and secrets are not copied. Pass the writer's workspace as reviewer
`cwd` and include the parent's `jj diff`; the read-only reviewer cannot run it.
The parent runs review test commands. Integration and workspace deletion require
explicit approval. Existing custom-delegate artifacts remain untouched.

Writers use attested acceptance instead of Git-index checks. Their reports are
claims, not independent verification; the parent reviews diffs and test evidence.

## Child environment

Children inherit repository and global instructions, but not the skills catalog.
Explicit extension allowlists load command guards; reviewers also load
`claude-code-pi@1.2.1`. Other ambient extensions are excluded. Reviewer model calls
use local `claude -p`; Claude Code must be installed and signed in. Read-only tool
selection is a workflow restriction, not a sandbox.

## Apply and test

Apply the Home Manager configuration, then restart Pi. This removes the managed
`delegate.ts` extension and enables upstream subagents. `/subagents-doctor` checks
the live setup. Existing sessions may retain obsolete tool declarations; use a
fresh session after switching.

```sh
node --experimental-strip-types --test home/agents/pi/{subagents,skill-policy,command-guards}.test.mjs
```

Set `PI_SDK_ENTRY` to Pi's `dist/index.js` and `PI_SUBAGENTS_DIR` to the installed
pi-subagents package to include upstream launch-contract checks. These make no
model requests.

# Skill policy

`skill-policy.ts` advertises the coding skills, Encore, Rex, and pi-subagents.
Other user skills require explicit invocation. Project-local and command-line
skills, and upstream explicit-only flags, remain unchanged.
