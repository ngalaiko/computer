# Feature tabs

Activation adopts the current Pi conversation and Rex tab as the feature coordinator. Keep the existing Pi process, conversation history, pane and shared session; create neither a tab nor a replacement Pi. Use one persistent task workspace per feature, with Vim text views or Oyo diffs in splits beside Pi. Setup and review are independent of the integration destination.

## Adopt the current tab

Require an actionable `/skill:feature` request with goal, scope, constraints and completion evidence. Requests to configure this workflow activate nothing.

Read `rex skill show` on the pane host. Verify this Pi's `REX_SESSION` and `REX_BLOCK` with:

```sh
rex block inspect -s "$REX_SESSION" "$REX_BLOCK" --json
rex block call -s "$REX_SESSION" -b "$REX_BLOCK" process
```

Take the full window ID from `.block.window_id`. Verify the live Pi process and PID, not app focus or a label. Resolve absent/stale context with `rex whoami --json`, `rex ls --json` and block/session inspection; ask on ambiguity. Missing or unverifiable Rex context blocks adoption; report it and ask rather than launching elsewhere.

Before adopting, inspect existing task ownership records, JJ workspaces and recorded coordinator processes. Verify task/repository identity, optional PR, workspace and live runtime IDs; guard against PID reuse. If another live Pi owns this task, hand off to that coordinator and stop implementation here. If this tab owns another unfinished feature, ask before changing ownership. Ambiguous ownership blocks adoption; never create a duplicate coordinator.

Read [Oyo review — Task workspace](oyo-review.md#task-workspace) to create or reuse the persistent task workspace. Record the source-relative subdirectory and verify it exists beneath the absolute task workspace. Keep Pi's original process cwd unchanged; use absolute task-workspace paths for file tools and `cd "$task_workspace" &&` for repository commands. Preserve source/default during implementation.

Save the verified session/window/block IDs, Pi PID and original process cwd in the task ownership record, marking the coordinator tab as adopted, not task-created. Preserve stable task key, workspace and bookmarks on resume. Recheck identity before updating stale runtime fields. Synchronize the tab and conversation title below, then report the adopted tab and task workspace. Continue implementation in this conversation.

## Tab title

The owning Pi keeps the Rex tab and Pi conversation on the same concise task + activity title, e.g. `review-flow: implementing`, `testing`, `review`, `blocked`, or `done`. Synchronize on adoption, resume and meaningful phase changes; skip unchanged names. Keep the task label recognizable; use `done` only after verified completion.

Read `rex window rename --help`. Before renaming, verify your own `REX_SESSION`/`REX_BLOCK` against the task ownership record with `rex block inspect`; take the full `window_id` from `.block.window_id`. Rename only that tab and set the current Pi conversation's name:

```sh
rex window rename -s "$REX_SESSION" "$window_id" "$title"
```

```js
set_session_name({ name: title });
```

Use the same concrete title in both calls. Read back Rex names with `rex session inspect "$REX_SESSION" --json` and verify the tool result before claiming synchronization. Record verified names without changing stable ownership fields. Report partial failures; retry only missing updates after ownership verification. A missing naming tool requires managed deployment and Pi reload; report it unavailable.

Preserve the shared session name and unrelated tabs. After adoption, unverifiable Rex context skips unsafe Rex title updates; Pi naming remains independent. Never infer ownership from focus.

## Show text and diffs

Keep concise discussion and the initial impact summary in Pi. When showcasing longer text, source, plans or evidence, use a Vim split in the adopted tab; use Oyo for implementation diffs under [Oyo review](oyo-review.md). Open views when useful or requested, not as a mandatory walkthrough. UI failures block only that view; report them without installing substitutes or opening another tab.

Prefer one showcase split at a time. Before switching between Vim and Oyo, close only the task-created prior view under its shutdown gates, including stopping Oyo delivery; preserve user-owned panes. Keep Pi readable rather than repeatedly splitting its remaining width.

Read `rex split --help`. Resolve the installed `vim` or `nvim` executable on the pane host and require an absolute executable path. Select the exact absolute file and line before opening; save generated review text outside repository workspaces. Open text read-only to protect the reviewed snapshot:

```sh
rex split -s "$REX_SESSION" -b "$REX_BLOCK" --split=right --ratio 67 -c "$task_workspace" --label Text --json -- "$vim_bin" -R -M "+$line" -- "$text_file"
```

Save `.block_ids[0]` and inspect the block: its `.block.window_id` must match Pi's verified tab. Check its process and capture before claiming the intended file/line is displayed. Record view ownership and exact file/snapshot in the task record. Reuse only a verified task-owned view; preserve user-owned panes and unsaved buffers. Before retrying a timeout, inspect existing blocks and processes to avoid duplicates. Never send editor commands to Pi's own pane.

Oyo owns its native-session, snapshot, file-coverage and watcher checks; a Vim view needs no Oyo watcher. Close only task-created view splits when finished, verifying termination before workspace cleanup. Preserve the adopted Pi tab, shared session and preexisting panes.

## Retention and cleanup

Retain the task workspace across review rounds and revisions under [Finishing](finishing.md). Adoption does not make the current Pi/tab disposable. Preserve this conversation and its original cwd; no coordinator exit is required merely to finish the task. Before workspace removal, verify no process cwd, UI, watcher or child uses it. If Pi itself uses that workspace as cwd, retain it until independently verified exit. Apply destination-specific completion, approval and recoverability gates; never remove live work or close the adopted tab as feature cleanup.
