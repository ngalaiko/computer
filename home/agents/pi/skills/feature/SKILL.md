---
name: feature
description: Develop and review isolated work, then merge locally or through GitHub.
disable-model-invocation: true
---

# Feature

Apply only to the task explicitly activated with `/skill:feature`. A verified coordinator resuming that task inherits activation. Requests to configure this workflow do not activate it; ordinary tasks stay in the current revision.

The parent coordinates; children follow their assigned role. Three states distinguish local preparation from approval:

- **Pending composition:** implementation and combined writer deltas inside task isolation; no integration approval needed.
- **Reviewed checkpoint:** pinned base, tip and tree with matching verification and independent review.
- **Approved destination integration:** explicit consent for that reviewed result and its destination under [Approval](finishing.md#approval).

## 1. Define

Establish goal, scope, constraints and acceptance criteria. Read [Verification and review](verification.md) to map criteria to checks and expected results and choose risk-based depth. Resolve material ambiguity before dispatch. Defer the local-versus-GitHub choice until approval unless already specified.

Read [Feature tabs](feature-tabs.md) to adopt the current Pi conversation and Rex tab; verify task ownership before implementation. Read [Rex activity](rex-activity.md) for milestone reporting. UI ownership and status never replace durable task identity or approval.

## 2. Isolate

Read [Task workspace](workspace.md) before repository edits or writer launches. Create or resume one persistent task workspace, with a stable intended base, task bookmark and ownership record. Use absolute assigned-workspace paths for file tools and `cd <assigned_workspace> &&` for repository commands; children retain the parent's cwd.

**Ready:** task identity, intended base, source identity, workspace and ownership are verified. Preserve source/default until approved local integration.

## 3. Implement and simplify

Delegate independent implementation and substantive review; keep trivial lookups in the parent. Inspect current role/model configuration and availability before dispatch; select explicitly:

| Role           | Assignment                                                                  |
| -------------- | --------------------------------------------------------------------------- |
| `explorer`     | Bounded read-only investigation.                                            |
| `small-worker` | Bounded, low-uncertainty edits.                                             |
| `worker`       | Implementation judgment; medium thinking, high for difficult work.          |
| `reviewer`     | Fresh read-only review; strongest available for broad or high-risk changes. |

Give each child a unique name and self-contained brief: goal, scope, constraints, absolute workspace/paths, expected result, checks and stop condition. Return ambiguity to the coordinator. Escalate a failed bounded attempt once rather than repeating it unchanged.

Serial writers reuse the task workspace, one writer at a time, including the parent. Writers leave one nonempty change at `@`, changed paths and test evidence; the coordinator owns checkpointing. Apply [snapshot preservation](workspace.md#use) before replacing failures or editing reviewed work; other incremental corrections may continue in place. Read [Parallel writers](parallel-work.md) only when implementation writers must run concurrently.

Use background agents while independent work remains; keep at most four children active. Otherwise yield for notification rather than polling. Retrieve full results, inspect actual changes, and use steering or resume for follow-ups.

Inspect the complete pending composition for redundant code, needless abstractions and avoidable indirection. Delegate substantive simplification. Preserve acceptance criteria, behavior and scope; record applied simplifications or a concrete no-change rationale. Repeat after corrections, before re-verification.

## 4. Verify and review

Follow [Verification and review](verification.md): check the complete composed delta, validate findings and enforce the three-round convergence cap. Hold the reviewed snapshot stable.

**Ready:** every acceptance criterion has observed evidence, required independent reviews are complete, and verified findings are addressed. Missing evidence or unresolved defects block readiness.

Read [Impact review](impact-review.md), present the initial summary in Pi, then wait for questions. Save evidence and summary together in the task review record. Requested changes return to implementation and affected verification.

Read [Oyo review](oyo-review.md) only for useful or requested implementation-diff drill-down. Optional UI failures do not block Pi discussion.

## 5. Approve destination

Resolve local versus GitHub from the explicit request or associated PR; ask only if unspecified. Obtain approval of the exact reviewed result and destination under [Finishing](finishing.md#approval). Review completion, comments and status events are not approval.

## 6. Integrate and close

Read [Finishing](finishing.md). The coordinator checkpoints, optionally refactors history, integrates and cleans up directly, using bounded preflight operations and verified postconditions. Substantial conflict resolution returns to implementation and review.

- **Local:** follow [Local-only integration and cleanup](finishing.md#local-only-integration-and-cleanup).
- **GitHub:** read [GitHub PR lifecycle](github-pr.md). Publication needs specific consent; pushes remain manual. Retain the task until verified merge or an explicit alternate ending.

**Complete:** report verified changes, tests, review outcome, thread counts (or unknown/unused), integration status and retained resources or blockers. For GitHub, include the PR URL and verified merge state. A checkpoint or open PR is not completion.

References are not independent skills. Resolve their links relative to this directory.
