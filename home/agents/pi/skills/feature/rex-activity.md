# Rex activity

Use Rex's Activity view and notifications rather than a separate attention queue. Pi already reports its native working, dialog, settled and error states through OSC 7501. A settled Pi turn is not a completed feature.

## Feature milestones

The parent-only `feature_status` tool adds one record, `id=feature`, in the current Pi terminal. It preserves Pi's native root record and every other pane's status. Use it only for the explicitly activated feature task, after verifying coordinator/tab ownership under [Feature tabs](feature-tabs.md).

On meaningful transitions, update the tab/Pi name first, then report the feature phase; not per command:

| Phase                                  | Rex state            | Use                                                                         |
| -------------------------------------- | -------------------- | --------------------------------------------------------------------------- |
| `implementing`, `testing`, `reviewing` | working              | Implementation, checks, fresh independent review.                           |
| `review-ready`                         | done                 | Verified impact summary has been presented; waiting for discussion.         |
| `question`                             | blocked / question   | A concrete answer is required to continue.                                  |
| `approval`                             | blocked / permission | Explicit approval has been requested for the exact changes and destination. |
| `auth`                                 | blocked / auth       | Required authentication is unavailable.                                     |
| `failed`                               | error                | Verification or another required operation failed and work stopped.         |
| `awaiting-merge`                       | idle                 | A published PR is awaiting external merge; not feature completion.          |
| `complete`                             | done                 | Destination-specific completion has been verified.                          |
| `clear`                                | clear                | Remove the feature record without clearing native Pi status.                |

```js
feature_status({ phase: "review-ready", message: "Impact summary ready" });
```

Use a concise, single-line message without secrets, customer data or raw error output. Status is not approval, permission to publish, or evidence that tests passed. Report `review-ready` only after the impact summary and verification evidence are available; after answering review questions, return to it unless a concrete answer or approval is required. Report `approval` only for an actual approval request, not simply because review ended. Keep blocked reasons accurate; do not manufacture questions to drive notifications.

The extension clears its record when a new agent run starts, a run is aborted, the session tree changes, or the Pi session starts/reloads/shuts down. Reassert the current milestone after processing follow-ups when still applicable. Reports are idempotent within a run; they do not claim Rex received them or showed a notification.

Verify reception using the owning Pi's exact IDs:

```sh
rex block call -s "$REX_SESSION" -b "$REX_BLOCK" program_status
```

Require the expected `feature` record and fields before claiming reception. A missing record, unsupported API, missing tool, noninteractive mode or disconnected Rex makes feature status unavailable; report that and continue the task safely. Apply managed deployment and reload Pi for a missing tool. Rex alone controls notification display, sounds and badges; do not add duplicate desktop alerts or change notification settings automatically. Names/status remain advisory; retain durable task records and snapshot checks.

## Activity navigation

Read `rex client ls --json` and the chosen client's `actions --json`. Use full client IDs when labels repeat; do not choose between multiple apps or steal focus. Supported clients expose `client.sidebar.activity.toggle`, `client.sidebar.activity.by_session`, and `client.sidebar.activity.by_priority`. Offer these as native ways to inspect feature tabs; execute UI actions only for an unambiguous requested target. Older connected clients may expose fewer actions than an updated app.

## Lifecycle checks

Use structured process/status APIs before terminal captures. `rex block call ... process` supplies the actual processes and `last_exit`; use it to verify coordinator startup and command termination. A reported `pwd` is shell-provided context, not proof of a process's cwd or workspace ownership.

For finite test/build commands that benefit from visible output, start a task-owned split beside Pi with `--keep-open --focus=false`. Record its IDs and use `rex wait -s SESSION BLOCK --for DURATION --json` for bounded waits, then inspect `process`/`last_exit` and relevant output. Timeout, lost connection or missing exit evidence is unknown, not success. Wait for the launched command, not a shell prompt or an interactive Pi turn.

Use `rex events -s SESSION --json` or scoped `rex do` Lua handlers when ongoing monitoring is useful. `terminal.program_status_changed` reports status, `terminal.child_exited` reports the terminal's launched process exit, and `block_closed`/`session_destroyed` invalidate recorded resources. A shell's individual commands do not each emit `terminal.child_exited`. Filter by exact recorded tab/block IDs, not labels or message text. Events are not a durable journal: after reconnect, re-read session view, processes and status before acting. Bound monitoring, record ownership, and stop it on task/session shutdown; never claim monitoring is active without a verified live observer. Use Lua actions for proven repeated mechanics, not a second autonomous orchestrator or a substitute for approval gates.
