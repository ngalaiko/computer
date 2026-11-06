---
name: feature
description: Develop and review isolated work, then merge locally or through GitHub.
disable-model-invocation: true
---

# Feature

Apply only to the task explicitly activated with `/skill:feature`. A verified coordinator resuming that task inherits activation; ordinary tasks stay in the current revision. Requests to configure this workflow do not activate it.

Parent Pi sessions coordinate this workflow. Child agents follow their assigned role.

## 1. Define the task

Establish the goal, scope, constraints and completion evidence. Ask about material ambiguity before dispatch. Use the same isolation, implementation and review flow for every feature. Defer the local-versus-GitHub choice to final integration; do not ask at task setup.

Read [Feature tabs](feature-tabs.md) to adopt the current Pi conversation and Rex tab as the coordinator; keep this process and history without launching another Pi or tab. Verify ownership before implementation; hand off if another live coordinator owns the task. Showcase text in Vim splits and implementation diffs in Oyo splits beside Pi under that reference. Keep the tab title synchronized with the Pi conversation's task + activity name on meaningful phase changes; preserve the shared session name.

For the verified coordinator, read [Rex activity](rex-activity.md) before work. Report feature milestones through Rex's native status record alongside name updates; use structured process/events APIs for lifecycle checks. Preserve Pi's native status and explicit approval gates.

## 2. Prepare isolation

Read [Oyo review — Task workspace](oyo-review.md#task-workspace) before repository edits or writer launches. Create or verify one persistent task workspace and its ownership record; reuse it across revisions. Select an explicit base and keep the default/source workspace untouched until approved local-only integration.

Use absolute task-workspace-rooted paths for parent file tools and `cd <task_workspace> &&` for repository commands. Preserve the source-relative subdirectory where applicable.

**Ready:** task identity, intended base, absolute workspace path, persistent bookmark and saved ownership record are verified, including the source root and working-copy identity.

## 3. Delegate

Resolve material ambiguity before assigning one-shot tasks. Delegate independent implementation, bounded edits and substantive review; keep trivial lookups in the parent.

| Role           | Use                                                                                |
| -------------- | ---------------------------------------------------------------------------------- |
| `explorer`     | Bounded codebase questions and noisy investigation; read-only.                     |
| `small-worker` | Bounded, low-uncertainty edits; escalate ambiguity to `worker`.                    |
| `worker`       | Cross-file implementation; set thinking to `medium`, or `high` for difficult work. |
| `reviewer`     | Fresh independent review; read-only.                                               |

Choose the role and model explicitly for each dispatch. Use `small-worker` for mechanical edits with complete acceptance criteria, `worker` for implementation or debugging judgment, and the strongest available reviewer for broad or high-risk review. A smaller reviewer may handle a narrowly scoped mechanical diff; preserve independent review. Return ambiguity to the coordinator and escalate a failed bounded attempt once rather than repeating the same cheap dispatch.

Verify availability of the four configured role models, especially `claude-code-cli/opus`, before dispatch: pins can fall back to the parent. Use `/agents` and FleetView to inspect conversations, progress and availability. Child extensions are limited to command guards; nested delegation and built-in Git worktree isolation are disabled.

### Workspace assignment

One persistent workspace per feature. Serial writers reuse the task workspace across implementation, retries and feedback rounds; only one writer may use the task workspace at a time, including the parent. Read-only agents use the workspace being inspected; hold its snapshot stable during review.

Additional workspaces are only for concurrent implementation writers whose changes need isolation. Reuse an idle task-owned parallel workspace only after its previous delta is integrated and recoverability verified; reset its empty working copy to the new `writer_base` before assignment. Otherwise create only the extra workspaces needed for that concurrency. Before branching, pause task writes and record the verified full commit ID of the current task snapshot as `writer_base`, including pending feature work. Record each parallel writer's base and assigned scope. Keep task `@` frozen until all parallel writers exit and their deltas are verified; concurrent writes use child workspaces. Preserve the base through reconciliation. Create from the pinned ID, not mutable task `@`:

```sh
cd "$task_workspace" && jj --config git.colocate=false workspace add --name <unique-name> -r "$writer_base" <absolute-child-path>
```

Keep child workspaces under `~/.pi/agent/jj-workspaces/`. Give each agent a unique name, short description and self-contained brief containing:

- Goal, scope, constraints and completion evidence.
- Assigned absolute workspace and file paths; shell commands begin with `cd <assigned_workspace> &&`. Agent has no cwd parameter: children retain the parent's cwd. These restrictions are prompt-only, not runtime isolation.
- Expected result and stop condition. Implementation writers leave one nonempty working-copy change at `@` for review, with changed paths and test evidence; the coordinator owns committing after approval. Before replacing a failed attempt, duplicate its snapshot into a separate recovery revision with a task-owned recovery bookmark; a bookmark on mutable `@` follows rewrites and does not preserve the attempt. Incremental corrections can continue in the same `@`. Report blockers rather than widening scope.

Use background agents and continue independent work. Keep at most four children active across foreground and background runs; upstream pools do not enforce this limit. When nothing independent remains, yield for completion notification rather than polling. Retrieve full results with `get_subagent_result`; use `steer_subagent` for running agents and `resume` for completed conversations.

## 4. Verify and review

Inspect actual changes against the brief; a child's summary is not evidence. Record relevant test outcomes against the snapshot and environment. Reuse verified evidence only for matching content, scope/base and environment; rerun affected checks after changes, not merely phase transitions. Start a fresh reviewer for each independent review, supplying requirements, absolute workspace path and its JJ diff, without implementation conversations or another agent's review history. The parent runs review test commands. Brief the independent reviewer on implementation defects and semantic impacts across the complete feature delta from its pinned base, not just the latest child delta.

**Ready for human review:** the diff matches scope, tests have recorded outcomes, and independent findings are addressed or explicitly reported as blockers. Do not claim readiness with missing evidence.

Read [Impact review](impact-review.md) before human review. Present the initial impact summary in Pi, then wait for questions; retain snapshot-bound evidence and explicit unknowns. Keep the reviewed workspace stable across turns. Requested edits follow Impact review's revision procedure.

Read [Oyo review](oyo-review.md) before opening the implementation diff in Rex, only for useful or requested drill-down. The parent owns UI and follows its snapshot, session and file-coverage checks before claiming the diff is loaded. After verifying native UI, explicitly start parent-only `oyo_watch` and read its initial result before claiming delivery active. If Oyo remains unopened, no watcher is required.

For saved feedback, follow Oyo review's discussion and native-reply procedure. Status-only events authorize neither replies nor integration/publication.

## 5. Consolidate

Read [Finishing](finishing.md) before integration or cleanup. The coordinator performs finishing directly: one scripted preflight per bounded operation, fixed commands and verified postconditions. Keep Rex/Oyo ownership, approval and final verification in the parent. Require explicit operator approval to integrate; review completion and resolved threads are not approval. Stop the watcher before integration or UI/workspace cleanup. Preserve recoverable pending work when blocked.

Consolidate approved changes in the persistent task workspace using [Integration](finishing.md#integration), retaining its identity across review rounds regardless of destination. Remove redundant child resources only under Finishing's cleanup gates; preserve the coordinator and approved work until final integration.

## 6. Refactor history (optional)

When useful or requested, follow [History refactoring](finishing.md#history-refactoring) in the task workspace before final integration. Preserve the approved result and verify the rewritten history before continuing.

## 7. Merge locally or through GitHub

Resolve the destination here, using an explicit request or associated PR when available; ask only if still unspecified. Require approval of the exact reviewed changes and destination.

- **Local:** follow [Local-only integration and cleanup](finishing.md#local-only-integration-and-cleanup), including verified source integration, explicit completion and coordinator-exit gates. PR-lifetime retention does not apply.
- **GitHub:** read [GitHub PR lifecycle](github-pr.md). Publish only with specific consent, integrate reviewed fixes into the same task revision, verify each published head, and retain the task until merge is verified or the operator explicitly chooses another ending. Pushes remain manual; never push to remote. Merge and outbound GitHub messages require their own consent. Report inactive merge monitoring explicitly.

Task-workspace consolidation and PR publication are intermediate states, not completion.

## 8. Close

**Complete:** report verified changes, tests, review outcome and unresolved thread counts (or unknown), integration status and retained resources or blockers. For GitHub integration, include the PR URL and verified merge state; an open PR remains awaiting merge. Never imply that local consolidation merged a PR or that cleanup published work.

The linked files are workflow references, not independent skills. Resolve their links relative to this file's directory, including when reading it directly.
