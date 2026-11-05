# Feature tabs

One feature per persistent task workspace and Rex tab in an existing shared session. Each feature tab contains its interactive Pi coordinator, with optional Oyo drill-down in a split on the right. Setup and review are independent of the final integration destination. Retain the coordinator through verified local integration or the associated PR's lifetime; follow [Finishing](finishing.md) for completion and teardown. A new feature is a separate interactive Pi process, not an Agent role or background subagent.

## Tab title

Name the feature tab at creation with `feature_label`. The owning Pi keeps the Rex tab and Pi conversation on the same task + activity title, e.g. `review-flow: implementing`, `testing`, `review`, `blocked`, or `done`. Synchronize after launch, on resume and on meaningful phase changes, not per command; skip unchanged names. Keep the task label recognizable through review, feedback, blocked and awaiting-merge states; use `done` only after verified completion.

Read `rex skill show` and `rex window rename --help`. Before renaming, verify your own `REX_SESSION`/`REX_BLOCK` and feature-tab ownership against the task ownership record using:

```sh
rex block inspect -s "$REX_SESSION" "$REX_BLOCK" --json
```

Take the full `window_id` from `.block.window_id`; the verified own pane is ownership evidence, and current task context supplies the title. No separate task-tab registry is required. Rename only the verified task-owned Pi tab; set the current Pi conversation's name through its native tool:

```sh
rex window rename -s "$REX_SESSION" "$window_id" "$title"
```

```js
set_session_name({ name: title });
```

Use the same concrete title in both calls. The tool uses Pi's live session API, persists the name and verifies it; no `/name` injection into a running terminal or direct session-file edits. Read back Rex names with `rex session inspect "$REX_SESSION" --json` and verify the tool result. Record the last verified names in the existing ownership record, keeping stable IDs, task key, workspace and bookmarks unchanged. Read back all names before claiming synchronization; report any partial update or failure and retry only the missing updates after ownership verification.

Never rename the shared session or an unrelated/focused tab. Session naming belongs to the operator. No Rex or missing/unverifiable context is nonblocking for title updates: skip only the unsafe Rex updates and report failures; never guess IDs. Pi naming remains independent of Rex. A missing `set_session_name` tool requires managed deployment and Pi reload; report Pi naming unavailable rather than claiming it updated. Session launch prerequisites below still apply.

## Prepare

Launch only for an actionable user feature request, not a request to configure this workflow. Require a self-contained feature brief with task, scope, constraints and completion evidence; ask only about material ambiguity. Never inherit or resume the caller's Pi conversation.

Read `rex skill show`, `rex window new --help` and `pi --help` on the target host. Resolve `pi_bin=$(command -v pi)` there; require an absolute executable path (`test -x "$pi_bin"`). Rex login PATH can differ; pass the resolved binary without changing its environment. Missing prerequisites block launch: report and await instructions, without installation or fallback to implementation in the caller.

Use the caller's verified `REX_SESSION` as `feature_session` for a new feature tab, not app focus. Keep its `REX_BLOCK` as source context only; the new Pi gets its own block ID. If context is absent/stale, use `rex whoami --json`, `rex ls --json` and session/block inspection; ask on ambiguity. Verify source paths and executable belong to that host.

## Create or reuse

Reuse the existing task workspace across review rounds and revisions. Before creating anything, inspect recorded task ownership and JJ workspaces; verify the task identity, associated PR if any, absolute workspace path and live coordinator/tab and its containing session. Inspect recorded Rex IDs and process cwd; verify process identity against PID reuse. With missing or stale runtime metadata, inspect process cwds and Rex listings. Ambiguous ownership blocks launch. Continue in its existing Pi tab when live; never launch a duplicate live coordinator. If this Pi is the verified task coordinator, continue without another launch. Otherwise hand off to the task coordinator and stop implementation in the caller.

Launch a new tab only when no live coordinator exists, under the launch conditions above. Reuse the recorded containing session when resuming a task; verify it still exists. Missing sessions or ambiguous destinations block launch until the operator selects an existing session. Do not create a session per feature or relaunch while another coordinator may be alive. Reuse the same task workspace; create one only for a feature without one. Additional writer workspaces follow [Workspace assignment](SKILL.md#workspace-assignment).

Load oyo-review's Task workspace procedure before tab launch to create or reuse the task workspace and its durable identity. Record the source-relative subdirectory; set `feature_workspace` to the verified absolute task workspace and `feature_cwd` to that workspace plus the subdirectory, checking it exists. Choose a short unique `feature_label`. Do not edit, switch or clean the original workspace.

On the target host, set `feature_skill="$HOME/.pi/agent/skills/feature/SKILL.md"` and require `test -r "$feature_skill"`. Keep this deployed path without resolving symlinks; never substitute a repository copy. Before launch, substitute the absolute `feature_skill` value into the brief below.

Build `brief` as one self-contained argument starting with the requested task, including task key, absolute feature workspace and source repo paths, scope, constraints and completion evidence. Include these coordinator instructions:

- This task carries the user's explicit feature-workflow activation. Read `<feature_skill>` before working; resolve its reference links against its containing directory.
- You own this persistent task workspace and Pi tab in a shared Rex session. Verify your own runtime identity and save it in the task ownership record before implementation. Keep it alive while Pi or tab is active and until Finishing's completion and teardown gates pass. Reuse it across review rounds and revisions; closing child review does not end the task.
- Work only in this feature workspace; assign children under SKILL.md's Workspace assignment policy. Child cleanup excludes this coordinator workspace. Keep default/source untouched until approved final local integration. Follow finishing.md for approved consolidation; defer the integration destination to the end.
- Maintain the Pi tab title and Pi conversation name with the same concise task + current activity using the Tab title procedure, including after startup, resume and feedback.
- Use your own `REX_SESSION`/`REX_BLOCK`, never the original caller IDs. Start human review with the impact summary in Pi. Optional Oyo belongs in a split beside Pi in your feature tab; follow oyo-review before opening it.

Start a fresh interactive Pi in a new feature tab using the installed help's `--name` and `--` message syntax:

```sh
rex window new -s "$feature_session" "$feature_label" -c "$feature_cwd" --json -- "$pi_bin" --name "$feature_label" -- "$brief"
```

Pass the brief as ONE argument, not `sh -c`; no `--print`, `inherit_context`, continuation or conversation resume. Rex supplies the new pane's own context; do not inject caller pane IDs into its environment or brief.

## Verify

Save returned `.window_id` and `.block_ids[0]` as the feature window and `feature_block`, together with the verified containing `feature_session`. Get the full window ID from `rex block inspect -s "$feature_session" "$feature_block" --json`. Inspect the new pane with `rex block call -s "$feature_session" -b "$feature_block" process` and `rex capture -s "$feature_session" -b "$feature_block" --trim`. Require a live interactive Pi with the intended name, cwd and initial task before reporting success; save coordinator runtime fields (session/tab/block IDs and PID) in the local ownership record after verified launch. The child may self-register the same verified identity; conflicting metadata blocks work.

New tabs take focus in their containing session. To show a resumed task in an app, inspect `rex client ls` and the selected client's `actions`; use documented `session.select` with explicit session/window IDs only when the client is unambiguous. Duplicate client labels require full IDs; ask before choosing between multiple apps. Never guess or claim a successful display switch without evidence.

On timeout, inspect session windows, processes and captures before any retry; avoid duplicate sessions or tabs. Retain a possibly live feature workspace. Retry startup in the same already-created feature workspace and containing session, not a new workspace or session. Every failure report includes evidence, workspace path/name and session/tab/block IDs; mark unknown IDs explicitly. Never close unrelated/current tabs or the caller's session. Report the created Pi tab, containing session and workspace, leaving the original untouched.

Exclude this coordinator workspace from child cleanup. Apply finishing.md's destination-specific completion and cleanup gates after final integration: local completion for local work, PR end for GitHub work. Require its Pi and tab to exit and another session to independently verify termination before teardown. Never remove a live coordinator cwd. Preserve consolidated changes, necessary task bookmarks and unrelated history; coordinator teardown alone never authorizes bookmark deletion. Preserve pending or failed work with a named recoverable bookmark unless the operator explicitly discards it. Feature cleanup never closes the shared Rex session; preserve its other tabs and processes.
