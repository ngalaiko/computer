# Parallel writers

Read before assigning concurrent implementation writers. Serial writers use the persistent task workspace under [Feature](SKILL.md#3-implement-and-simplify).

## Branch

Pause task writes and pin the full commit ID of the current pending task snapshot as `writer_base`, including pending feature work. Record each writer's base and scope. Keep task `@` frozen until all parallel writers exit and their deltas are verified; read-only review also requires a stable snapshot.

Create only the extra workspaces needed for concurrent writers, under `~/.pi/agent/jj-workspaces/`. Reuse an idle task-owned workspace only after its previous delta is composed and recoverability verified; reset its empty working copy to the pinned base. Otherwise create from the full ID:

```sh
cd "$task_workspace" && jj --config git.colocate=false workspace add --name <unique-name> -r "$writer_base" <absolute-child-path>
```

Apply the dispatch brief and one-change-at-`@` contract from [Feature](SKILL.md#3-implement-and-simplify). Assigned paths and command prefixes are prompt restrictions, not runtime isolation. Record exact workspace and temporary review-bookmark ownership.

## Compose

After every writer exits, inspect each full base-to-tip delta and test evidence. A child with multiple changes violates the assignment contract: stop and ask rather than silently taking only `@`. Preserve pinned bases through reconciliation.

Combine only each writer's delta into the task workspace; include shared pending work once. This is **pending composition**, not destination integration, and needs no integration approval. Apply [Finishing operations](finishing.md#operation) for bounded mutations and preflight. Preserve recoverable child snapshots until the combined result is verified.

Resolve conflicts as implementation. Simplify, test and independently review the complete combined feature delta under [Verification and review](verification.md), then present [Impact review](impact-review.md). Approval applies to that combined result, not separately reviewed fragments.

Remove redundant children only under [Cleanup](finishing.md#cleanup).
