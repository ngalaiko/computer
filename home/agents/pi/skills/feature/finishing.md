# Finishing

Read before checkpointing, integration, history rewriting or cleanup. [Task workspace](workspace.md) owns identity/isolation; [Verification and review](verification.md) owns evidence; this file owns approval, mutations and resource lifecycle.

## Approval

Pending composition inside task isolation may combine writer deltas before approval. It preserves the approved checkpoint and source/default. Review the complete composed result before requesting approval.

Destination integration requires explicit operator approval of the reviewed base-to-tip result and destination. Save the approved full identities and tree in the ownership record. Review completion, resolved threads, status events and workflow activation are not approval. Content or destination changes require renewed approval; identity-only checkpoint/history changes may proceed only after verified tree and complete-diff equivalence.

Outbound messages, including native Oyo replies, require consent for that specific message. Remote writes also require specific operation consent. Pushes remain manual. Local checkpointing is neither publication nor PR merge.

## Operation

The coordinator performs composition reconciliation, checkpointing, integration, history rewriting and cleanup directly. Delegate substantial implementation/conflict resolution to a writer; retain UI ownership and final verification in the parent.

1. Define one bounded operation: exact resources, destination, fixed commands, preconditions and postconditions. Verify ownership, recoverability and applicable approval. Stop writers, reviews and Oyo delivery before mutating their snapshots; verify process quiescence.
2. Run [Scripted preflight](#scripted-preflight) once against current pins. Check each command's result before dependent work; expected changes within the operation need no intermediate manifest.
3. Stop on identity drift, expanded scope, failure, conflicts or ambiguous ownership. Preserve recoverable work and replan; never regenerate expected pins merely to pass a failed check.
4. Verify full resulting identities, history/tree, bookmark targets and removed/retained resources. Inspect affected revisions/descendants with JJ's `conflicts()` revset after history mutations; exit zero does not prove conflict-free history. Record partial completion on failure.

Conflict resolution returns to implementation in task isolation, affected checks and independent review. Changed approved content requires renewed approval. After rewriting ancestors, reconcile disposable child working copies with `jj workspace update-stale` only after ownership verification and writer exit; do not update source/default.

## Scripted preflight

Create a parent-owned JSON manifest outside repository workspaces and run the checker resolved relative to this reference:

```sh
node /absolute/feature/scripts/finishing-check.mjs /absolute/finishing-manifest.json
```

Fields:

- `version`: `1`.
- `operation`: `integration` (also composition/checkpoint/history operations) or `cleanup`.
- `snapshots`: nonempty array of `{ "workspace": "/absolute/canonical/root", "commit": "FULL_COMMIT_ID", "change": "FULL_CHANGE_ID" }`. Pin source, task, affected children and destination.
- Cleanup only: `cleanup`: `{ "root": "/absolute/canonical/workspace-container", "protectedWorkspaces": ["/absolute/source", "/absolute/task", "/absolute/coordinator"], "workspaces": [{ "name": "exact-child-name", "path": "/absolute/canonical/child" }], "bookmarks": ["exact-temporary-bookmark"], "revisions": ["FULL_COMMIT_ID"] }`. Empty target arrays are valid. Every protected root needs a snapshot pin. Protect source, persistent task workspace and live coordinator during disposable-child cleanup. Persistent task teardown and removal of any `task/` bookmark remain parent-only operations under lifecycle gates.

Stop writers and snapshot/inspect disk immediately before pinning and again before mutation. The checker uses read-only JJ commands with `--ignore-working-copy`: it checks stored snapshots, does not lock resources, and cannot detect later disk edits.

Failure blocks the operation. Success proves only preflight, not approval, ownership, process termination, redundancy or content equivalence. Independently verify those gates and the exact target list. The checker rejects every `task/` bookmark cleanup target, including pending refs; remove those only under the parent-only gate below. It also refuses direct revision targets of preserved workspaces and unrelated local/remote bookmarks; a selected local bookmark's `@git` ref is its local mirror. It permits recorded conflicts only in selected disposable cleanup snapshots/revisions. Abandoning failed work still requires recovery or explicit discard.

Execute only fixed commands/resource lists. One child `jj workspace forget` plus exact-directory removal joined with `&&` is a command unit; all units in one bounded cleanup share a preflight. Stop on failure. Verify completed units before omitting them from a subsequent manifest; a forgotten workspace cannot pass registration preflight again.

## Integration

Serial and reconciled parallel work already reside in the persistent task workspace. [Parallel writers](parallel-work.md) owns pre-review composition. After [approval](#approval), checkpoint the exact reviewed result into atomic, bisectable task commits. Include only recorded task-owned changes and preserve the intended base and unrelated history.

Verify complete base-to-tip diff and final tree against the reviewed checkpoint. Reuse evidence only under [Verification and review](verification.md); changed content/context needs affected checks and independent re-review. Commit nonempty work with `jj commit -m "…"`, leaving an empty undescribed `@`. Point the persistent task bookmark at the recorded described tip, verify its target, and record full commit/change IDs. Remove redundant pending refs only under Cleanup.

This approved checkpoint is not destination integration. Keep the persistent task workspace through review rounds and GitHub publication. Default/source remains unchanged until local integration below.

## History refactoring

Optionally squash, split, reorder or reword task-owned revisions before destination integration. Confirm material history-shape changes with the operator; rewriting published history requires explicit approval. Use Operation and preserve approved tip/base/tree, unrelated history and atomic, bisectable commits.

Verify conflict-free history, identical final tree and complete base-to-tip diff. Content changes return to verification and approval. Leave `@` empty and undescribed, update the persistent bookmark to the described tip, and record new identities. Remove redundant revisions under Cleanup. Publication must verify the rewritten head; pushes remain manual.

## Local-only integration and cleanup

After approval of the exact result and local destination, verify the recorded source identity against current source/default. Stop on unrelated work, drift or ambiguous destination. This is the only operation permitted to change source/default.

Integrate only approved changes, preserving unrelated history. Apply Operation and refresh evidence for changed integration context. Commit nonempty integrated work with `jj commit -m "…"`; leave source/default `@` empty and undescribed. Verify the integrated full identities and result before reporting integration.

Task teardown additionally requires explicit user completion and Cleanup's recoverability/process gates. Remove only redundant task resources, preserving integrated history, unrelated resources and empty default `@`. Incomplete integration retains named recoverable work. Report cleanup failures and retained resources separately from integration success.

## Cleanup

Disposable child cleanup may follow verified reconciliation without another approval prompt; it never discards the only recoverable copy. Persistent task teardown follows destination-specific completion gates. Closing review alone authorizes neither.

For each operation, record exact task-owned workspace names/paths, bookmarks and full revision IDs. Verify processes, UI, watchers and children have terminated or released the resource. Preserve source/default, integrated task history and ancestors, unrelated refs/remotes, active/shared workspaces and any ref used by another workspace. Use exact targets, not broad patterns or revsets.

After redundancy is verified, remove task-created temporary bookmarks, forget exact child workspaces, remove exact directories and abandon only recorded redundant task-owned revisions. Superseded implementation copies, empty successors and failed trials are eligible only when redundant or explicitly discarded. Verify protected resources and report remaining clutter/blockers rather than claiming cleanup complete.

After verifying exact ownership, redundancy/recovery, process release and current pins, the parent may remove exact pending `task/` refs outside child-cleanup manifests. Persistent task refs additionally require the destination completion gates below. Pending/unintegrated/failed work retains a named recoverable bookmark unless explicitly discarded. Keep the persistent task bookmark for approved work, the pending bookmark for serial pending work, and recovery refs for replaced failures. Children whose deltas are not yet composed may be removed only after user completion and process termination, with recoverable revisions retained. A verified composed delta satisfies the disposable-child reconciliation gate. Keep the persistent task workspace while work remains pending, except explicit GitHub teardown below.

The adopted Pi conversation/tab and shared Rex session survive cleanup. Verify no process cwd, view, watcher or child uses the task workspace before removing it. Never delete a live cwd; retain it until independently verified exit. For old task-created coordinators, read [Legacy teardown](legacy-teardown.md).

### GitHub retention

Retain the task workspace through open-PR review rounds. Teardown requires explicit operator confirmation that the PR has ended and the process gates above. Preserve consolidated/pending recoverable revisions. The persistent PR bookmark survives workspace teardown until integration into intended target history is verified, or the operator explicitly discards the work.

GitHub merge status alone does not prove local target-history inclusion. Verify the recorded revision or reviewed squash/rebase equivalent in the intended target history. Fetch requires specific consent; if unavailable, retain the bookmark and ownership record and report local verification blocked.

Remove the ownership and combined review records only after the persistent bookmark is safely removed or work explicitly discarded. For operator-requested benchmarking, read [Benchmarking](benchmarking.md); its records survive task cleanup.
