# Verification and review

## Plan the evidence

Before dispatch, map each acceptance criterion to an executable check or observable interaction, its exact command/procedure and expected result. Inspect the project's existing checks; reuse them. For a bug fix, observe a regression check fail for the reported defect before implementation, then pass with the fix. Explain any unavailable check and leave its criterion unverified. Ask the operator to supply evidence, choose an alternative check or explicitly amend acceptance criteria. Record the decision and remaining risk; an amendment is not a passing check and cannot waive repository safety gates.

Choose verification depth from the complete delta's blast radius; reassess after scope changes:

| Risk                                                                                          | Required evidence                                                                                                 |
| --------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Routine: bounded change within one contract                                                   | Focused checks and independent implementation review.                                                             |
| Cross-boundary: callers, persistence, configuration or external contracts                     | Routine evidence plus affected-consumer/compatibility checks and an end-to-end check of the changed path.         |
| Sensitive: authorization, secrets, billing, destructive data changes, CI or release machinery | Cross-boundary evidence plus a fresh security-focused review, failure-path checks and recovery/rollback evidence. |

Use the highest applicable tier. Risk changes check depth, not isolation, explicit approval or publication rules. A check must observe the intended state, not merely a successful request or process startup.

## Record results

Inspect actual changes against the brief; a child's summary is not evidence. The coordinator runs review commands and inspects their results. Preserve records beside the task ownership record, outside repository workspaces, in the combined task review record, `~/.pi/agent/jj-workspaces/<key>-review.md`:

- Acceptance criteria, risk tier and rationale.
- Workspace, full snapshot/base IDs, checked scope and relevant environment/tool versions.
- Each command or interaction, expected result, actual result, exit status when applicable and output/artifact reference. Preserve red/green evidence for bug fixes.
- Failures, skipped checks and unverified behavior; unknown is not passed.
- Review rounds, findings and dispositions; applied simplifications or a concrete no-change rationale.
- The current [impact summary](impact-review.md), decisions and approved checkpoint/destination, when available.

Record `review_base`, `review_tip` and tree in the ownership record; the complete review range is independent of whether `@` is empty. Reuse evidence only when content, checked scope/base and environment match. After changes, rerun affected checks and refresh the record; phase transitions alone require no rerun. Drift pauses readiness. Retain the record through blocked work; remove it only with task ownership-record cleanup under [Finishing](finishing.md).

## Independent review

Hold the inspected snapshot stable. Start a fresh read-only reviewer with requirements, risk tier, absolute workspace, full snapshot/base IDs and JJ diff. Supply source and evidence references, not implementation conversations or another reviewer's reasoning. The reviewer reports concrete defects and semantic impacts with file/line evidence, failure conditions and severity; exclude stylistic preferences already covered by deterministic checks.

The first pass covers the complete feature delta from its pinned base, including prior task revisions, affected callers, contracts, configuration and indirect consequences. For sensitive changes, use a separate fresh security reviewer; the coordinator verifies that review's findings too.

Verify every candidate against source, reproduction or recorded checks before sending work to a writer. Track a stable finding ID, affected bug class, evidence, disposition and round in the review record. Fix verified defects across the affected class; reject false positives with evidence. Report unresolved defects as blockers. Keep earlier findings in the same review record and deduplicate repeats rather than assigning them again.

## Convergence

After a correction, use a fresh reviewer for the correction delta and affected contracts, with original requirements and access to the complete feature delta. Widen to full-delta review when scope, architecture or risk changes, or integration changes the context. Retain initial full-delta coverage; a narrow re-review cannot replace it. A verified fix must cover the underlying defect, not only silence the previous report.

Stop when required checks pass and all verified findings are addressed. One clean review is enough; extra rounds are not mandatory. Count implementation-review passes within one correction cycle, including retries, feedback fixes received before that cycle passes, and conflict resolution; parallel specialist reviews of the same snapshot count as one round. A cycle ends when checks and review pass. Later requested changes start a new cycle; scope changes within a failing cycle do not reset its count. After three rounds that still leave verified defects, pause implementation and review, preserve recoverable work, and present the remaining defects and an alternative approach. Continue only after the operator chooses a direction; record that decision before resetting the failed cycle's count. A passing third round may proceed normally. The cap never waives missing evidence or approval.

When a failure recurs, prefer an executable check or narrow documented gotcha at its authoritative source over another general instruction. Change workflow policy only within the operator's requested scope.

**Ready:** every acceptance criterion has observed evidence, required independent reviews are complete, and verified findings are addressed. Missing evidence or unresolved defects block readiness; disclose them in the impact summary without claiming review-ready.
