---
name: feature-tabs
description: Start another feature in a separate Rex tab with an independent interactive Pi and long-lived JJ workspace.
---

# Feature tabs

One feature per Rex tab: interactive parent Pi on the left, Oyo on the right only during review. A new feature is a separate interactive Pi process, not an Agent role or background subagent. Existing one-shot worker workspace policy stays unchanged.

## Prepare

Launch only for an actionable user feature request, not a request to configure this workflow. Require a self-contained feature brief with task, scope, constraints and completion evidence; ask only about material ambiguity. Never inherit or resume the caller's Pi conversation.

Read `rex skill show`, `rex window new --help` and `pi --help` on the target host. Resolve `pi_bin=$(command -v pi)` there; require an absolute executable path (`test -x "$pi_bin"`). Rex login PATH can differ; pass the resolved binary without changing its environment. Missing prerequisites block launch: report and await instructions, without installation or fallback.

Use the caller's valid `REX_SESSION` to select the same Rex session, not app focus. If context is absent/stale, use `rex whoami --json`, `rex ls --json` and session/block inspection; ask on ambiguity. Verify source paths and executable belong to that host.

## Create

From the caller's working directory, record the absolute source repo/workspace root (`jj root`), source change (`jj log -r @ --no-graph`) and source-relative subdirectory. Choose unique `workspace_name` and absolute `feature_workspace` under `~/.pi/agent/jj-workspaces/`, plus a short `feature_label`. From that source workspace:

```sh
jj --config git.colocate=false workspace add --name "$workspace_name" -r @ "$feature_workspace"
```

Verify the new root/change; set `feature_cwd` to the feature workspace plus the source-relative subdirectory, checking it exists. Do not edit, switch or clean the original workspace.

Build `brief` as one self-contained argument starting with the requested task, including absolute feature workspace and source repo paths, scope, constraints and completion evidence. Include these coordinator instructions:

- You own this live feature workspace/tab; keep the workspace alive while Pi or tab is active, until the user ends the feature.
- Work only in this feature workspace; children use separate one-shot JJ workspaces. Child cleanup excludes this coordinator workspace. No automatic integration; explicit operator approval remains required.
- Use your own `REX_SESSION`/`REX_BLOCK`, never the original caller IDs. You own review UI beside your Pi in this tab; use oyo-review when child changes are ready.

Start a fresh interactive session using the installed help's `--name` and `--` message syntax:

```sh
rex window new -s "$REX_SESSION" "$feature_label" -c "$feature_cwd" --json -- "$pi_bin" --name "$feature_label" -- "$brief"
```

Pass the brief as ONE argument, not `sh -c`; no `--print`, `inherit_context`, continuation or conversation resume. Normal Rex focus changes are allowed. Rex supplies the new pane's own context; do not inject caller pane IDs into its environment or brief.

## Verify

Save returned `.window_id` and `.block_ids[0]` plus workspace/name and task ownership. Inspect the new pane with `rex block call -s "$REX_SESSION" -b "$feature_block" process` and `rex capture -s "$REX_SESSION" -b "$feature_block" --trim`. Require a live interactive Pi with the intended name, cwd and initial task before reporting success.

On timeout, inspect session windows, processes and captures before any retry; avoid duplicate tabs. Retain a possibly live feature workspace. Retry startup in the same already-created feature workspace, not a new one. Every failure report includes evidence, workspace path/name and session/tab/block IDs; mark unknown IDs explicitly. Never close unrelated/current tabs. Report the created tab and workspace, leaving the original untouched.

Exclude this coordinator workspace from child cleanup. Retain it until the user explicitly ends the feature, then require its Pi and tab to exit and another session to independently verify termination before teardown. Never remove a live coordinator cwd. Apply oyo-review cleanup: remove task-created refs/revisions and exact workspace after verified integration; preserve pending or failed work with a named recoverable bookmark unless the operator explicitly discards it.
