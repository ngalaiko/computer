# Impact review

Human review starts in Pi with consequences, not a file list or code diff. Keep independent implementation review and tests; the summary is an entry point, not proof or integration approval.

## Prepare

After writers exit, complete [Verification and review](verification.md), including full-feature coverage and validated findings. Build the impact summary from the matching snapshot's review record; preserve its criterion/check mapping, risk tier and unknowns.

Record the base, full reviewed commit/change IDs, workspace, scope and verification environment. Hold the snapshot stable across questions; recheck identity before answering or showing evidence. Drift pauses review until affected verification and the summary are refreshed.

## Present

Post the initial summary in Pi automatically when implementation and review evidence are ready. Report `review-ready` under [Rex activity](rex-activity.md) only when [Verification and review](verification.md)'s Ready criterion holds. For a blocked summary, report `question` when an operator decision is needed, otherwise `failed`; describe the missing evidence or unresolved defects. Keep feature completion distinct from a settled Pi turn. Lead with consequential risks or blockers. Always cover Behavior, Verification and Decisions. Include other categories only when affected or materially uncertain; use one or two sentences per included category:

```text
Impact review

Behavior: What changes for users or systems; important preserved behavior.
Database: Schema/data changes, backfills, locking, data loss, compatibility.
API/events: Before/after contracts, affected consumers, errors and compatibility.
Infrastructure: Resources created/replaced/deleted, permissions, exposure, cost.
Security: Authorization, trust boundaries, secrets and sensitive-data handling.
Operations: Deployment order, observability, recovery and rollback.
Verification: Checks and results; unverified behavior and missing evidence.
Decisions: Unresolved choices requiring human judgment, or none.
```

For included categories, describe changed impacts, important preserved behavior or material unknowns. Omit unaffected categories rather than filling a checklist. Separate evidence-backed facts from predictions and unknowns. Explain before/after behavior rather than listing files. Link consequential claims to relevant tests, command output, contracts, migrations, plans or source locations. Use available structured checks; no new tools, services or uploads are required. Redact secrets and sensitive data from evidence.

Update the summary section of the combined `~/.pi/agent/jj-workspaces/<key>-review.md` record. Preserve its verification evidence, findings, snapshot references and unresolved decisions across turns.

## Discuss

Let the user ask questions naturally; wait after the summary rather than starting a mandatory walkthrough. Answer the requested topic with before/after behavior, consequences and evidence; inspect source or run relevant safe checks when needed. Keep answers scoped, and label anything unverified.

Use diagrams, API examples or migration details when useful for the requested drill-down or explicitly requested. Showcase longer text in a read-only Vim split under [Feature tabs](feature-tabs.md#show-text-and-diffs); use [Oyo review](oyo-review.md) for implementation diffs. Oyo prerequisites block that UI only, not the summary or chat discussion. Follow Oyo's target-specific feedback procedure; Git ranges use on-demand reads. Without an opened Oyo session, no watcher or thread queries are required.

## Revise and finish

For requested edits, preserve the reviewed snapshot under [Workspace](workspace.md#use) and pause review; stop any active Oyo watcher before writes. Reuse the task workspace and pending revision, delegate the edits, rerun affected checks and follow [Convergence](verification.md#convergence) for independent re-review. Update the pending snapshot record, preserve the approved task tip, and refresh any verified open Oyo session under its feedback procedure. Present what changed since the previous review, updated impacts, verification and remaining decisions; update the saved summary before continuing questions.

Review completion and resolved comments are not approval. Follow [Approval](finishing.md#approval) for the exact reviewed result and destination. If Oyo was opened, follow its thread reporting and UI shutdown gates; otherwise report Oyo unused, not zero unresolved threads. Remove the saved review artifact only with task ownership-record cleanup under Finishing's completion and recoverability gates.
