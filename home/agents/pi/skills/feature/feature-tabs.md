# Feature tabs

One feature per persistent task workspace and dedicated Rex session. The session contains the interactive coordinator's Pi tab, with optional Oyo drill-down in a split on the right. Setup and review are independent of the final integration destination. Retain the coordinator through verified local integration or the associated PR's lifetime; follow [Finishing](finishing.md) for completion and teardown. A new feature is a separate interactive Pi process, not an Agent role or background subagent.

## Tab title

Name the feature session at creation with a concise task label; name its initial tab `Pi`. The owning Pi keeps a concise task + current activity tab title, e.g. `review-flow: implementing`, `testing`, `review`, `blocked`, or `done`. Update on meaningful phase changes, not per command; skip unchanged titles.

Read `rex skill show` and `rex window rename --help`. Before renaming, verify your own `REX_SESSION`/`REX_BLOCK` against the task ownership record using:

```sh
rex block inspect -s "$REX_SESSION" "$REX_BLOCK" --json
```

Take the full `window_id` from `.block.window_id`; the verified own pane is ownership evidence, and current task context supplies the title. No separate task-tab registry is required. Rename only that verified owned tab:

```sh
rex window rename -s "$REX_SESSION" "$window_id" "$title"
```

Never rename the session or an unrelated/focused tab based on focus. No Rex or missing/unverifiable context is nonblocking for title updates: skip the update and report failures; never guess IDs. Session launch prerequisites below still apply.

## Prepare

Launch only for an actionable user feature request, not a request to configure this workflow. Require a self-contained feature brief with task, scope, constraints and completion evidence; ask only about material ambiguity. Never inherit or resume the caller's Pi conversation.

Read `rex skill show`, `rex new --help`, `rex window new --help` and `pi --help` on the target host. Resolve `pi_bin=$(command -v pi)` there; require an absolute executable path (`test -x "$pi_bin"`). Rex login PATH can differ; pass the resolved binary without changing its environment. Missing prerequisites block launch: report and await instructions, without installation or fallback to implementation in the caller.

Use the caller's valid `REX_SESSION`/`REX_BLOCK` only to identify the source, not as the feature destination. If context is absent/stale, use `rex whoami --json`, `rex ls --json` and session/block inspection; ask on ambiguity. Verify source paths and executable belong to that host.

## Create or reuse

Reuse the existing task workspace across review rounds and revisions. Before creating anything, inspect recorded task ownership and JJ workspaces; verify the task identity, associated PR if any, absolute workspace path and live coordinator/session/tab. Inspect recorded Rex IDs and process cwd; verify process identity against PID reuse. With missing or stale runtime metadata, inspect process cwds and Rex listings. Ambiguous ownership blocks launch. Continue in its existing Pi tab when live; never launch a duplicate live coordinator. If this Pi is the verified task coordinator, continue without another launch. Otherwise hand off to the task coordinator and stop implementation in the caller.

Create a new session only when no verified task-owned session exists. Never adopt the caller's shared session as `feature_session`. If a retained task-owned session has no live coordinator, reuse it by opening a new Pi tab there. Do not relaunch while another coordinator may be alive. Reuse the same task workspace; create one only for a feature without one. Additional writer workspaces follow [Workspace assignment](SKILL.md#workspace-assignment).

Load oyo-review's Task workspace procedure before session launch to create or reuse the task workspace and its durable identity. Record the source-relative subdirectory; set `feature_workspace` to the verified absolute task workspace and `feature_cwd` to that workspace plus the subdirectory, checking it exists. Choose a short unique `feature_label`. Do not edit, switch or clean the original workspace.

On the target host, set `feature_skill="$HOME/.pi/agent/skills/feature/SKILL.md"` and require `test -r "$feature_skill"`. Keep this deployed path without resolving symlinks; never substitute a repository copy. Before launch, substitute the absolute `feature_skill` value into the brief below.

Build `brief` as one self-contained argument starting with the requested task, including task key, absolute feature workspace and source repo paths, scope, constraints and completion evidence. Include these coordinator instructions:

- This task carries the user's explicit feature-workflow activation. Read `<feature_skill>` before working; resolve its reference links against its containing directory.
- You own this persistent task workspace, dedicated Rex session and Pi tab. Verify your own runtime identity and save it in the task ownership record before implementation. Keep it alive while Pi or tab is active and until Finishing's completion and teardown gates pass. Reuse it across review rounds and revisions; closing child review does not end the task.
- Work only in this feature workspace; assign children under SKILL.md's Workspace assignment policy. Child cleanup excludes this coordinator workspace. Keep default/source untouched until approved final local integration. Follow finishing.md for approved consolidation; defer the integration destination to the end.
- Maintain your tab title with concise task + current activity using the Tab title procedure.
- Use your own `REX_SESSION`/`REX_BLOCK`, never the original caller IDs. Start human review with the impact summary in Pi. Optional Oyo belongs in a split beside Pi in your dedicated session; follow oyo-review before opening it.

Start a fresh interactive Pi in a new feature session using the installed help's `--name` and `--` message syntax:

```sh
rex new "$feature_label" --window Pi -c "$feature_cwd" --json -- "$pi_bin" --name "$feature_label" -- "$brief"
```

For a verified retained task session without a live coordinator, set `feature_session` to its full recorded ID and use:

```sh
rex window new -s "$feature_session" Pi -c "$feature_cwd" --json -- "$pi_bin" --name "$feature_label" -- "$brief"
```

Pass the brief as ONE argument, not `sh -c`; no `--print`, `inherit_context`, continuation or conversation resume. Rex supplies the new pane's own context; do not inject caller pane IDs into its environment or brief.

## Verify

For `rex new`, save `.session_id` as `feature_session` and `.initial_windows[0].block_ids[0]` as `feature_block`. For a new tab in a retained session, save `.block_ids[0]`. Get the full window ID from `rex block inspect -s "$feature_session" "$feature_block" --json`. Inspect the new pane with `rex block call -s "$feature_session" -b "$feature_block" process` and `rex capture -s "$feature_session" -b "$feature_block" --trim`. Require a live interactive Pi with the intended name, cwd and initial task before reporting success; save coordinator runtime fields (session/tab/block IDs and PID) in the local ownership record after verified launch. The child may self-register the same verified identity; conflicting metadata blocks work.

A new Rex session is not automatically displayed by the app. Read `rex client ls` and the selected client's `actions`; when the target client is unambiguous, use its documented `session.select session_id=...` action and verify the selected session. Ask when client selection is ambiguous; do not guess or claim a successful display switch without evidence.

On timeout, inspect session windows, processes and captures before any retry; avoid duplicate sessions or tabs. Retain a possibly live feature workspace. Retry startup in the same already-created feature workspace and task session, not a new one. Every failure report includes evidence, workspace path/name and session/tab/block IDs; mark unknown IDs explicitly. Never close unrelated/current tabs or the caller's session. Report the created feature session, Pi tab and workspace, leaving the original untouched.

Exclude this coordinator workspace from child cleanup. Apply finishing.md's destination-specific completion and cleanup gates after final integration: local completion for local work, PR end for GitHub work. Require its Pi and tab to exit and another session to independently verify termination before teardown. Never remove a live coordinator cwd. Preserve consolidated changes, necessary task bookmarks and unrelated history; coordinator teardown alone never authorizes bookmark deletion. Preserve pending or failed work with a named recoverable bookmark unless the operator explicitly discards it. Close the feature Rex session only with explicit user consent, verified ownership and no unrelated tabs/processes; never kill the active coordinator's own session as routine cleanup.
