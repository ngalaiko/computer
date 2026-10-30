# Finishing

Read before approved integration, history rewriting or cleanup. [Oyo review](oyo-review.md) owns workspace setup and human review; this file owns finishing gates. Local consolidation is not publication or PR merge.

## Operation

The coordinator performs integration, history rewriting and cleanup directly. Keep Rex tab/pane ownership, Oyo feedback and watcher control in the coordinator. Delegate substantial implementation or conflict resolution to `worker`; use `small-worker` for substantial mechanical edits, not routine finishing commands.

1. Define one bounded operation: exact changes/resources, destination, commands, preconditions and postconditions. Establish approval, ownership, recoverability and process termination before mutation. Stop writers and the Oyo watcher; verify task-owned reviews/processes are quiescent.
2. Run [Scripted preflight](#scripted-preflight) once before each bounded operation against current pins. Expected changes within the operation need no intermediate manifest or handoff. Check each command's result before dependent work.
3. Stop on unexpected identity drift, scope expansion, command failure, ambiguous ownership, integration/history conflicts or unrecorded cleanup conflicts. Preserve recoverable work and replan; never broaden cleanup or retry destructively. Never regenerate expected pins merely to make a failed check pass.
4. Verify the postconditions: resulting full identities, history/tree, bookmark targets, protected resources and removed/retained resources. Inspect affected revisions/descendants with JJ's `conflicts()` revset after history mutations; exit status zero does not prove a conflict-free result. Record partial completion on failure.

Conflict resolution is implementation, not approved finishing: brief `worker` for conflict resolution in retained task isolation, then repeat affected verification and obtain approval of the changed result. Cleanup may retain or remove a recorded conflicted failed trial only under the recoverability/discard gates below; it never resolves conflicts.

## Verification evidence

Reuse recorded tests and independent review only when content, reviewed scope/base and environment match the resulting operation. A phase change alone does not require a rerun. Changed content or integration context requires affected tests and fresh independent review; content changes also require renewed approval. Always verify identities and final integration postconditions. Missing evidence remains a blocker.

## Scripted preflight

Resolve `scripts/finishing-check.mjs` against this reference's directory. Store a parent-created JSON manifest outside every repository workspace, then run:

```sh
node /absolute/feature/scripts/finishing-check.mjs /absolute/finishing-manifest.json
```

Manifest fields:

- `version`: `1`.
- `operation`: `integration` (also for history rewriting) or `cleanup`.
- `snapshots`: nonempty array of `{ "workspace": "/absolute/canonical/root", "commit": "FULL_COMMIT_ID", "change": "FULL_CHANGE_ID" }`. Pin source, task, affected children and destination; use actual full IDs, not these placeholders.
- For cleanup only, `cleanup`: `{ "root": "/absolute/canonical/workspace-container", "protectedWorkspaces": ["/absolute/source", "/absolute/coordinator"], "workspaces": [{ "name": "exact-child-name", "path": "/absolute/canonical/child" }], "bookmarks": ["exact-temporary-bookmark"], "revisions": ["FULL_COMMIT_ID"] }`. Empty target arrays are valid. Every protected root must also have a snapshot pin. Keep source and live coordinator protected; scope routine cleanup to disposable children. Coordinator teardown and persistent-task-bookmark deletion stay in the parent under the lifecycle gates below.

Snapshot and inspect working trees immediately before recording pins. The checker uses read-only JJ commands with `--ignore-working-copy`: pins describe stored JJ snapshots, not unsnapshotted disk edits. Stop writers first; repeat parent disk/snapshot checks immediately before mutation. The checker does not lock resources or close this race.

A failed check blocks the operation. A successful check is only preflight evidence, not approval or proof of ownership, process termination, redundancy or content equivalence. The parent independently verifies those gates and the proposed target list. The checker refuses direct revision targets of preserved workspaces and unrelated local/remote bookmarks; an explicitly selected local bookmark's `@git` backing ref is its local mirror, not an independent remote. It allows recorded conflicts only in selected disposable cleanup snapshots/revisions. Removing a workspace may preserve its bookmarked conflicted work; abandoning that work requires the separate recovery/discard gates. The checker performs no integration, deletion, bookmark movement or abandonment. Execute only the operation's fixed commands and resource list; stop and replan on unexpected results. Verify final identities and protected resources before beginning another operation. A child workspace-forget plus exact-directory removal is one explicitly approved shell command unit joined with `&&`; all units in the fixed cleanup operation share its single preflight. Verify each unit's outcome and stop on failure. Record partial completion on failure; a forgotten workspace cannot pass workspace-registration preflight again. Subsequent manifests omit completed targets only after parent verification.

## Operation record

For delegated work, record model, elapsed time, retries and coordinator corrections at `~/.pi/agent/finishing-trials/<task-key>.jsonl`, outside task workspaces. Include detailed token/cost data only when automatically available. Records survive task cleanup and ownership-record deletion; exclude them from cleanup manifests. Missing metrics remain unknown.

## Revision safety

Before rewriting the PR revision (integration or coordinator direct edits), stop or finish other task writers and watchers/reviews using descendants; never mutate under active children. Afterwards reconcile affected disposable child working copies with `jj workspace update-stale` only after exact ownership verification and worker exit. Do not update the default/source workspace. Rerun affected snapshot identity checks; reuse tests and independent review only under Verification evidence before continuing.

## Local-only integration and cleanup

Keep default/source unchanged during implementation and review. After explicit approval of the exact reviewed changes and destination, stop task writers, watchers and reviews before integration. Verify the recorded source identity against the current default workspace; stop on unrelated work, changed identity or ambiguous destination. Only this approved local-only integration may change default/source.

Integrate only the recorded approved changes, preserving unrelated history. The coordinator handles conflicts under Operation and repeats affected tests and independent review before reporting verified integration. Commit nonempty integrated work with `jj commit -m "…"`; leave default `@` empty and undescribed. Verify the integrated changes and record their full identities before cleanup.

Cleanup additionally requires explicit user completion. Apply the Cleanup section's ownership, exact-resource scoping, recoverability and process-termination gates, but not PR-lifetime retention. A dedicated coordinator Pi/tab must exit; another session must independently verify termination before removing its workspace. An external coordinator must verify no process, UI, watcher or child uses the task workspace. Never delete a live cwd.

After verified integration and these gates, remove only task-created redundant revisions, bookmarks, workspaces and ownership records. Preserve integrated changes, unrelated resources and the empty default `@`. Retain named recoverable work if integration is incomplete or fails. Report retained resources and cleanup failures; cleanup never publishes work.

## Integration

For PR-backed tasks, a task means one pull request (PR), not one revision. Retain the persistent PR task workspace across review rounds and revisions; temporary writer workspaces remain separate. Closing a child review does not end the PR.

Integration requires explicit operator approval. Explicitly stop `oyo_watch` and verify it stopped before any integration rebase or consolidation. Resume only explicitly after reverified native UI if still reviewing. A multi-change child violates the one-working-copy contract: stop, report and ask; never silently integrate only `@` or consolidate an unverified stack.

After approved identity/review/tests, consolidate all approved work into one JJ revision for that PR in its task workspace unless the operator specifies otherwise. Include previously approved PR work and approved changes from different child workspaces for the same PR; child commit boundaries are disposable. Never combine different PRs. Verify the PR identity, exact approved child changes, existing PR revision and intended base before mutation; stop and ask if ownership or scope is ambiguous. Reuse the existing PR task workspace and update its PR revision rather than creating a workspace or commit per review round. Never integrate into or move the default/source workspace; preserve its working-copy commit and history.

Rebase approved inputs onto the intended PR base as needed, then consolidate only the recorded approved PR changes in the task workspace. The coordinator handles conflicts under Operation and repeats affected tests/independent review before proceeding; reverify identity if the snapshot changed. Verify the complete consolidated PR diff using [Verification evidence](#verification-evidence) before declaring integration verified; reuse matching tests/review evidence, and rerun affected checks when content or integration context changes. Commit nonempty consolidated work with `jj commit -m "…"`, leaving an empty undescribed `@`. The persistent task bookmark must follow the described consolidated PR revision; set it to that recorded full commit ID in the verified task workspace and verify its target. Record the integrated full change/commit IDs and verify history/tree before cleanup. Local child consolidation is not actual PR integration in target history. Completion or resolution alone never approves this operation.

## History refactoring

Optionally squash, split, reorder or reword feature-branch revisions after PR consolidation and before publication. Local-only history rewriting happens in the task workspace before approved source integration; never rewrite default/source under this step. Confirm the intended history shape with the operator; retain the default single-revision PR shape unless instructed otherwise. Apply Revision safety before rewriting and scope changes to recorded task-owned revisions; preserve the intended base and unrelated history. Rewriting published history requires explicit approval; pushes remain manual.

Record the approved tip, base and tree before rewriting. Verify the resulting history is conflict-free and its final tree and complete base-to-tip diff match the approved result. Content changes require affected tests, fresh independent review and renewed integration approval. Commit nonempty work with `jj commit -m "…"`, leaving `@` empty and undescribed; point the persistent task bookmark at the described tip. Record its updated full commit/change IDs and remove redundant task-owned revisions under Cleanup. Published-head verification must use the rewritten identity.

## Cleanup

After explicit integration approval and verified integration, remove redundant task resources outside the feature branch as part of integration, not at PR closure. Disposable child cleanup needs no separate user-completion gate; active review/UI/process gates still apply. Local-only task and coordinator teardown retain their explicit completion gates. Before teardown, record task ownership, exact bookmark/workspace names, full change IDs, and exact workspace directory. Distinguish disposable child workspaces from the persistent PR coordinator. Scope every JJ ref/revision operation to those recorded task resources; avoid broad patterns and revsets.

Temporary review bookmarks are distinct from the persistent PR bookmark. For integrated child work, remove task-created local temporary review bookmarks after recording the consolidated identity. Remove only redundant task-owned revisions: superseded implementation copies, empty successors, and superseded trials or failed trials. After verified termination of task-owned UI, watches and processes, use `jj workspace forget` for only the exact disposable child workspace, remove its exact directory, and abandon the recorded redundant task-owned revisions with `jj abandon`. Verify no integrated child workspace, temporary bookmark or redundant revision remains outside the feature branch; report blocked cleanup rather than claiming completion. Preserve the consolidated PR revision and its ancestors, default/source history, main refs, unrelated bookmarks/remotes, and active/shared/source workspaces or refs used by other active workspaces. Leave no permanent backup or review-bookmark clutter; the persistent PR identity bookmark is not disposable backup clutter.

For pending, unintegrated, or failed work, retain a named recoverable bookmark unless the operator explicitly discards it. Use the persistent PR bookmark for consolidated or coordinator work; retain only necessary temporary bookmarks for unintegrated child work, not per-child backups after consolidation. Preserve the pending or failed revision and bookmark. For unintegrated work, only disposable child workspaces are eligible for removal after user completion and verified process termination; retain the PR coordinator. Report retained work and cleanup failures. Cleanup never integrates or pushes.

Retain the persistent PR task workspace across review rounds and revisions, including after child review closure or approved consolidation. Teardown requires the operator to explicitly confirm the PR has ended. A dedicated feature Pi/tab must exit, with another session that independently verifies termination. For an external parent coordinating without a dedicated Pi/tab, verify no process cwd, UI, watch or active child uses the exact task workspace before teardown. Do not close the external parent's main Pi or tab. After the PR has ended and these process gates pass, use `jj workspace forget` for the exact coordinator workspace and remove its exact directory, preserving the consolidated PR revision and any pending recoverable work. The local ownership record also survives coordinator teardown while the PR ref is needed. The persistent PR bookmark survives coordinator teardown; never delete the sole PR ref merely because local consolidation or review is complete. Delete the persistent PR bookmark only after actual PR integration in target history is verified, or the operator explicitly discards the PR work. Verify the recorded PR revision is included in the intended target history (or its reviewed equivalent if rewritten), not merely in the local coordinator. Remove the ownership record only when the PR bookmark is safely removed or the work explicitly discarded. Remote operations still require specific consent. Closing review does not integrate or authorize integration; add no walkthrough approval prompt.
