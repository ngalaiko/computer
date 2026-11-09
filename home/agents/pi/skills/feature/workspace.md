# Task workspace

Read before repository edits or writer launches. [Feature tabs](feature-tabs.md) owns coordinator adoption; this file owns task identity and isolation. [Finishing](finishing.md) owns approval and cleanup.

## Identity

Choose a stable unique task key before a PR exists. Store machine identity outside the repository at `~/.pi/agent/jj-workspaces/<key>.json`:

- Task key, repository identity, source root and recorded source working-copy identity; optional PR URL.
- Intended base, workspace name and canonical absolute path; persistent bookmark `task/<key>`.
- Adopted coordinator's Rex session/window/block IDs, Pi PID and original cwd. Track optional view block IDs and Oyo native session separately.
- Pending snapshot, reviewed checkpoint (`review_base`, `review_tip`, tree), and approved checkpoint/destination as separate full identities.
- Task-owned child workspaces, bases, temporary/recovery bookmarks and resources when present.

Keep evidence, findings, simplification rationale and human summary together in `<key>-review.md` beside this record, under [Verification and review](verification.md). On resume, merge any legacy `<key>-verification.md` evidence into the review record before retiring the duplicate; preserve provenance and unresolved findings.

Inspect existing records, `jj workspace list`, `jj bookmark list` and `jj log -r <task-bookmark>` before creation or resume. Verify repository/task/PR identity, paths, working-copy revision, bookmark and live coordinator. Ask on missing paths, conflicting identity or ambiguous ownership; hand off if another live coordinator owns the task. Reuse the task key and workspace across revisions.

## Create

Only if no matching task exists, select a stable intended base without unrelated source work. Choose a unique workspace name and absolute path under `~/.pi/agent/jj-workspaces/`. Record source identity, then create from the verified source root:

```sh
jj --config git.colocate=false workspace add --name "$workspace_name" -r "$task_base" "$task_workspace"
```

Verify `jj root`, `jj workspace list` and `jj log -r @` in the new workspace, then create the persistent bookmark at the base:

```sh
cd "$task_workspace" && jj bookmark create "$task_bookmark" -r "$task_base"
```

Save verified identity and coordinator ownership. Preserve the source-relative subdirectory and verify it exists in the task workspace.

## Use

Use absolute assigned-workspace-rooted file paths and `cd "$task_workspace" &&` for repository commands; Pi's original cwd stays unchanged. Keep source/default untouched until approved [local integration](finishing.md#local-only-integration-and-cleanup).

The persistent bookmark identifies the approved task tip, initially the intended base. Pending composition may change task `@` without moving the approved bookmark. Keep `task/<key>/pending` on the latest pending serial snapshot; verify and record its full identity before session end or blocked integration. Serial checkpoints may create an empty successor; subsequent edits use that successor while preserving approved history. Move the persistent bookmark only after [approved checkpointing](finishing.md#integration).

Before replacing a failed attempt or editing a reviewed checkpoint in place, duplicate it into a separate recovery revision with a non-`task/` bookmark. Record original/recovery IDs and verify parent, tree and diff equivalence; use the preserved copy for correction comparisons. A bookmark on mutable `@` follows rewrites and does not preserve the snapshot. Use temporary bookmarks for parallel child review. Remove pending/recovery refs only under [Cleanup](finishing.md#cleanup).

Record the complete review range from intended base to pending or committed tip, independent of whether `@` is empty. Hold that checkpoint stable during review; drift requires affected verification and an updated summary. A task bookmark or successful command alone proves neither ownership nor reviewed content.
