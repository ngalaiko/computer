# Impact review

Human review starts in Pi with consequences, not a file list or code diff. Keep independent implementation review and tests; the summary is an entry point, not proof or integration approval.

## Prepare

After writers exit and verification finishes, inspect the complete feature delta against its pinned base, including prior task revisions. Give the fresh independent reviewer the requirements, base and snapshot IDs, absolute workspace and JJ diff. Ask for implementation defects and semantic impacts, including affected callers, contracts, configuration and indirect consequences. The coordinator verifies the findings against source and recorded checks.

Record the base, full reviewed commit/change IDs, workspace, scope and verification environment. Hold the snapshot stable across questions; recheck identity before answering or showing evidence. Drift pauses review until affected verification and the summary are refreshed.

## Present

Post the initial summary in Pi automatically when implementation and review evidence are ready. After presenting it, report `review-ready` under [Rex activity](rex-activity.md); keep feature completion distinct from a settled Pi turn. Lead with consequential risks or blockers. Use one or two sentences per category:

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

Cover every category: describe changed impacts, checked—unchanged surfaces, or unknown areas. Separate evidence-backed facts from predictions and unknowns. Explain before/after behavior rather than listing files. Link consequential claims to relevant tests, command output, contracts, migrations, plans or source locations. Use available structured checks; no new tools, services or uploads are required. Redact secrets and sensitive data from evidence.

Save the summary and its snapshot/evidence references outside every repository workspace, beside the task ownership record as `~/.pi/agent/jj-workspaces/<key>-review.md`. Refresh this artifact with the presented review; retain unresolved decisions and verification gaps across turns.

## Discuss

Let the user ask questions naturally; wait after the summary rather than starting a mandatory walkthrough. Answer the requested topic with before/after behavior, consequences and evidence; inspect source or run relevant safe checks when needed. Keep answers scoped, and label anything unverified.

Use diagrams, API examples or migration details when useful for the requested drill-down or explicitly requested. Showcase longer text in a read-only Vim split under [Feature tabs](feature-tabs.md#show-text-and-diffs); use [Oyo review](oyo-review.md) for implementation diffs. Oyo prerequisites block that UI only, not the summary or chat discussion. Start its watcher only after verifying native UI; without an opened Oyo session, no watcher or thread queries are required.

## Revise and finish

For requested edits, record the reviewed snapshot and pause review; stop any active Oyo watcher before writes. Reuse the task workspace and pending revision, delegate the edits, rerun affected checks and obtain fresh independent review. Update the pending snapshot record, preserve the approved task tip, and refresh any verified open Oyo session under its feedback procedure. Present what changed since the previous review, updated impacts, verification and remaining decisions; update the saved summary before continuing questions.

Review completion and resolved comments are not approval. Require explicit operator approval of the exact reviewed changes and destination under [Finishing](finishing.md). If Oyo was opened, follow its thread reporting and UI shutdown gates; otherwise report Oyo unused, not zero unresolved threads. Remove the saved review artifact only with task ownership-record cleanup under Finishing's completion and recoverability gates.
