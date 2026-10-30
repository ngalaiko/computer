---
name: feature
description: Start isolated work, coordinate review and integration, and optionally follow a GitHub PR through merge.
disable-model-invocation: true
---

# Feature

Apply only to the task explicitly activated with `/skill:feature`. A coordinator launched for that task inherits activation; ordinary tasks stay in the current revision. Requests to configure this workflow do not activate it.

Parent Pi sessions coordinate this workflow. Child agents follow their assigned role.

## 1. Define the task

Establish the goal, scope, constraints and completion evidence. Ask about material ambiguity before dispatch. Distinguish a local-only task from a PR; one PR may span several review rounds. Ask whether GitHub publication and follow-through are wanted; publishing is optional.

Keep a concise task + activity tab title on meaningful phase changes. Read [Feature tabs](feature-tabs.md#tab-title) for ownership checks and updates. Read its launch procedure only when starting a separate interactive coordinator; another tab is optional.

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

Choose the role and model explicitly for each dispatch. Use `small-worker` for mechanical edits with complete acceptance criteria, `worker` for integration or debugging judgment, and the strongest available reviewer for broad or high-risk review. A smaller reviewer may handle a narrowly scoped mechanical diff; preserve independent review. Return ambiguity to the coordinator and escalate a failed bounded attempt once rather than repeating the same cheap dispatch.

Verify availability of the four configured role models, especially `claude-code-cli/opus`, before dispatch: pins can fall back to the parent. Use `/agents` and FleetView to inspect conversations, progress and availability. Child extensions are limited to command guards; nested delegation and built-in Git worktree isolation are disabled.

Before each implementation writer launch, resolve the verified persistent task bookmark to its full commit ID as `writer_base`; require it matches the recorded approved revision or initial intended task base. Create a unique temporary JJ workspace from that pinned revision, not mutable task `@`. Finishing executors instead operate only on the exact approved resources in their [Finishing contract](finishing.md#executor-contract):

```sh
cd "$task_workspace" && jj --config git.colocate=false workspace add --name <unique-name> -r "$writer_base" <absolute-child-path>
```

Keep child workspaces under `~/.pi/agent/jj-workspaces/`. Give each agent a unique name, short description and self-contained brief containing:

- Goal, scope, constraints and completion evidence.
- Assigned absolute workspace and file paths; shell commands begin with `cd <assigned_workspace> &&`. Agent has no cwd parameter: children retain the parent's cwd. These restrictions are prompt-only, not runtime isolation.
- Expected result and stop condition. Implementation writers leave one nonempty working-copy change at `@` for review, with changed paths and test evidence; finishing executors return the contract's exact identities and resource outcomes. Report blockers rather than widening scope.

Use background agents and continue independent work. Keep at most two children active across foreground and background runs; upstream pools do not enforce this limit. When nothing independent remains, yield for completion notification rather than polling. Retrieve full results with `get_subagent_result`; use `steer_subagent` for running agents and `resume` for completed conversations.

## 4. Verify and review

Inspect actual changes against the brief; a child's summary is not evidence. Run the relevant tests in the assigned workspace. Start a fresh reviewer for each independent review, supplying requirements, absolute workspace path and its JJ diff, without implementation conversations or another agent's review history. The parent runs review test commands.

**Ready for human review:** the diff matches scope, tests have recorded outcomes, and independent findings are addressed or explicitly reported as blockers. Do not claim readiness with missing evidence.

Read [Oyo review](oyo-review.md) before opening the child diff in Rex. The parent owns UI and protects the reviewed workspace from readiness through user completion. Follow its snapshot, session and file-coverage checks before claiming the diff is loaded.

After verifying native UI, explicitly start parent-only `oyo_watch` with the exact workspace, native session and trusted executable. Read its initial result before claiming delivery active. A missing tool requires Pi reload; report delivery inactive and use on-demand reads. Restart only explicitly after fresh verification.

For saved feedback, follow Oyo review's discussion and native-reply procedure. Status-only events authorize neither replies nor integration/publication. Requested edits follow the linked feedback procedure: writer, tests, fresh independent review, bookmark update and verified live-session refresh.

## 5. Integrate

Read [Finishing](finishing.md) before integration or cleanup. Follow its executor contract and scripted preflight; keep approval, ownership decisions and final verification in the parent. Require explicit operator approval to integrate; review completion and resolved threads are not approval. Stop the watcher before integration or UI/workspace cleanup. Preserve recoverable pending work when blocked.

For a PR, consolidate approved changes in the persistent task workspace and retain its identity across review rounds. After verified integration, remove redundant task workspaces, bookmarks and revisions outside the feature branch under Finishing's cleanup gates. Child cleanup excludes the PR coordinator; PR-lifetime retention applies only to actual PRs.

For local-only work, follow [Local-only integration and cleanup](finishing.md#local-only-integration-and-cleanup), including explicit completion and coordinator-exit gates. PR-lifetime retention does not apply.

## 6. Refactor history (optional)

When useful or requested, follow [History refactoring](finishing.md#history-refactoring) to squash, reorder or reword the feature branch before publication. For local-only work, perform this step in the task workspace before step 5's approved source integration. Preserve the approved result and verify the rewritten history before continuing.

## 7. Publish and follow through (optional)

When GitHub publication or an existing PR is explicitly requested, read [GitHub PR lifecycle](github-pr.md). Publish only with specific consent, integrate reviewed fixes into the same task revision, verify each published head, and retain the task while awaiting merge. Pushes remain manual; never push to remote.

A published PR is not completion. Follow the fix/review loop until merge is verified or the operator explicitly chooses another ending. Merge and outbound GitHub messages require their own consent; the workflow does not authorize either. Report when merge monitoring is inactive rather than implying unattended follow-through.

## 8. Close

**Complete:** report verified changes, tests, review outcome and unresolved thread counts (or unknown), integration status and retained resources or blockers. For the optional GitHub branch, include the PR URL and verified merge state; an open PR remains awaiting merge. Never imply that local consolidation merged a PR or that cleanup published work.

The linked files are workflow references, not independent skills. Resolve their links relative to this file's directory, including when reading it directly.
