# Feature tabs

One feature per persistent task workspace and Rex tab: interactive parent Pi on the left, Oyo on the right only during review. Setup and review are independent of the final integration destination. Retain the coordinator through verified local integration or the associated PR's lifetime; follow [Finishing](finishing.md) for completion and teardown. A new feature is a separate interactive Pi process, not an Agent role or background subagent.

## Tab title

`feature_label` is the initial title; the owning Pi makes dynamic updates after launch. Keep a concise task + current activity, e.g. `review-flow: implementing`, `testing`, `review`, `blocked`, or `done`. Update on meaningful phase changes, not per command; skip unchanged titles. This applies to existing parent tabs too, without launching another tab.

Read `rex skill show` and `rex window rename --help`. Before renaming, verify your own `REX_SESSION`/`REX_BLOCK` using:

```sh
rex block inspect -s "$REX_SESSION" "$REX_BLOCK" --json
```

Take the full `window_id` from `.block.window_id`; the verified own pane is ownership evidence, and current task context supplies the title. No separate task-tab registry is required. Rename only that verified owned tab:

```sh
rex window rename -s "$REX_SESSION" "$window_id" "$title"
```

Never rename the session or an unrelated/focused tab based on focus. No Rex or missing/unverifiable context is nonblocking: skip the update and report failures; continue the task without creating UI or guessing IDs.

## Prepare

Launch only for an actionable user feature request, not a request to configure this workflow. Require a self-contained feature brief with task, scope, constraints and completion evidence; ask only about material ambiguity. Never inherit or resume the caller's Pi conversation.

Read `rex skill show`, `rex window new --help` and `pi --help` on the target host. Resolve `pi_bin=$(command -v pi)` there; require an absolute executable path (`test -x "$pi_bin"`). Rex login PATH can differ; pass the resolved binary without changing its environment. Missing prerequisites block launch: report and await instructions, without installation or fallback.

Use the caller's valid `REX_SESSION` to select the same Rex session, not app focus. If context is absent/stale, use `rex whoami --json`, `rex ls --json` and session/block inspection; ask on ambiguity. Verify source paths and executable belong to that host.

## Create or reuse

Reuse the existing task workspace across review rounds and revisions. Before creating anything, inspect recorded task ownership and JJ workspaces; verify the task identity, associated PR if any, absolute workspace path and live coordinator/tab. Inspect recorded Rex IDs and process cwd; verify process identity against PID reuse. With missing or stale runtime metadata, inspect process cwds and Rex listings; ambiguity blocks launch. Continue in its existing tab when live; never launch a duplicate live coordinator. Launch a new tab only under the launch conditions above, when no live coordinator exists; reuse the same task workspace. Ambiguous ownership blocks launch. Create a task workspace only for a feature without one; additional writer workspaces follow [Workspace assignment](SKILL.md#workspace-assignment).

Load oyo-review's Task workspace procedure before tab launch to create or reuse the task workspace and its durable identity. Record the source-relative subdirectory; set `feature_workspace` to the verified absolute task workspace and `feature_cwd` to that workspace plus the subdirectory, checking it exists. Choose a short `feature_label`. Do not edit, switch or clean the original workspace.

On the target host, set `feature_skill="$HOME/.pi/agent/skills/feature/SKILL.md"` and require `test -r "$feature_skill"`. Keep this deployed path without resolving symlinks; never substitute a repository copy. Before launch, substitute the absolute `feature_skill` value into the brief below.

Build `brief` as one self-contained argument starting with the requested task, including absolute feature workspace and source repo paths, scope, constraints and completion evidence. Include these coordinator instructions:

- This task carries the user's explicit feature-workflow activation. Read `<feature_skill>` before working; resolve its reference links against its containing directory.
- You own this persistent task workspace/tab; keep it alive while Pi or tab is active and until Finishing's completion and teardown gates pass. Reuse it across review rounds and revisions; closing child review does not end the task.
- Work only in this feature workspace; assign children under SKILL.md's Workspace assignment policy. Child cleanup excludes this coordinator workspace. Keep default/source untouched until approved final local integration. Follow finishing.md for approved consolidation; defer the integration destination to the end.
- Maintain your tab title with concise task + current activity using the Tab title procedure.
- Use your own `REX_SESSION`/`REX_BLOCK`, never the original caller IDs. You own review UI beside your Pi in this tab; use oyo-review when child changes are ready.

Start a fresh interactive session using the installed help's `--name` and `--` message syntax:

```sh
rex window new -s "$REX_SESSION" "$feature_label" -c "$feature_cwd" --json -- "$pi_bin" --name "$feature_label" -- "$brief"
```

Pass the brief as ONE argument, not `sh -c`; no `--print`, `inherit_context`, continuation or conversation resume. Normal Rex focus changes are allowed. Rex supplies the new pane's own context; do not inject caller pane IDs into its environment or brief.

## Verify

Save returned `.window_id` and `.block_ids[0]` plus workspace/name and task ownership. Inspect the new pane with `rex block call -s "$REX_SESSION" -b "$feature_block" process` and `rex capture -s "$REX_SESSION" -b "$feature_block" --trim`. Require a live interactive Pi with the intended name, cwd and initial task before reporting success; save the optional dedicated coordinator runtime fields in the local ownership record after verified launch.

On timeout, inspect session windows, processes and captures before any retry; avoid duplicate tabs. Retain a possibly live feature workspace. Retry startup in the same already-created feature workspace, not a new one. Every failure report includes evidence, workspace path/name and session/tab/block IDs; mark unknown IDs explicitly. Never close unrelated/current tabs. Report the created tab and workspace, leaving the original untouched.

Exclude this coordinator workspace from child cleanup. Apply finishing.md's destination-specific completion and cleanup gates after final integration: local completion for local work, PR end for GitHub work. Require its Pi and tab to exit and another session to independently verify termination before teardown. Never remove a live coordinator cwd. Preserve consolidated changes, necessary task bookmarks and unrelated history; coordinator teardown alone never authorizes bookmark deletion. Preserve pending or failed work with a named recoverable bookmark unless the operator explicitly discards it.
