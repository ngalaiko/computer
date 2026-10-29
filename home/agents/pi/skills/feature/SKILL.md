---
name: feature
description: Opt-in feature workflow with isolated JJ workspaces, delegation, and Oyo review.
disable-model-invocation: true
---

# Feature

Apply this workflow only to the task explicitly activated by the user with `/skill:feature`. A coordinator launched through that activated workflow inherits activation for the same task. Ordinary tasks stay in the current revision without this workflow.

Read [Oyo review](oyo-review.md) for workspace setup, review, feedback, integration and cleanup. Read [Feature tabs](feature-tabs.md) for tab titles or a separate interactive coordinator. These files are workflow references, not independent skills. Resolve relative links against the directory containing this file, including when reading it directly.

<delegation>
Parent Pi sessions only. Child agents follow their assigned role instead.
- Delegate independent implementation, bounded edits, and substantive review with Agent using subagent_type explorer, worker, small-worker, or reviewer. Supply a unique name, short description, and a self-contained prompt stating goal, scope, constraints, paths, expected evidence, and stop condition. Use explorer for bounded codebase questions and noisy investigation; keep trivial lookups in main. Use small-worker for bounded, low-uncertainty edits and worker for cross-file implementation. Pass worker thinking: "medium" normally or "high" for difficult implementation; its frontmatter leaves effort caller-selectable. Escalate ambiguous small-worker tasks to worker.
- Before each writer launch, create a unique temporary JJ workspace from the PR task working-copy change (`cd "$task_workspace" && jj --config git.colocate=false workspace add --name <unique-name> -r @ <absolute-path>`). Keep workspaces under ~/.pi/agent/jj-workspaces/. Supply its absolute path; require absolute file paths and `cd <workspace> &&` for shell commands. Children retain the parent's cwd: Agent has no cwd parameter. These are prompt-only workspace restrictions, not runtime isolation. Preserve the source-relative subdirectory when applicable.
- Children execute one-shot tasks and return their final results; resolve material ambiguity before dispatch. Use background Agent calls, continue independent work, then yield for the completion notification rather than polling. Retrieve full output with get_subagent_result using agent_id. Use steer_subagent for corrections during a run; Agent resume continues a completed conversation. Keep at most two children active across foreground and background runs as parent policy; upstream pools are separate and do not enforce that combined limit.
- Start a new reviewer for each independent review; provide requirements, the workspace's absolute path, and its jj diff, not the implementation conversation or another agent's history. Explorer and reviewer have read-only built-in tools; the parent runs review test commands.
- Use one persistent task workspace per pull request, reused across review rounds and revisions; keep the default/source workspace untouched. Temporary writer workspaces stay separate. Parent file tools must use absolute task-workspace-rooted paths; relative read/edit/write paths would touch default. When starting or resuming a task, load oyo-review for task workspace setup before any writer launch; also load it before integration or cleanup. Integration requires explicit operator approval. Child cleanup covers only task-created child workspaces, not the PR coordinator.
- For local-only tasks without a PR, approved integration into default completes the task. After verifying integration and stopping task-owned processes, remove task-created workspaces, bookmarks, ownership records and redundant revisions; preserve integrated changes and the empty default `@`. PR-lifetime retention rules apply only to actual PRs.
- Keep your own Rex tab title aligned with concise task + current activity on meaningful phase changes; load feature-tabs for ownership checks and title updates.
- When starting another feature in a separate tab, load feature-tabs for an independent interactive Pi and long-lived JJ workspace.
- When a child is ready for human review, load oyo-review and open its diff in Rex; the parent owns UI.
- For saved Oyo thread feedback, load oyo-review: after verified native UI, explicitly start parent-only oyo_watch with its exact workspace/session/executable and read the initial result before claiming delivery active. Missing tool requires Pi reload; report delivery inactive. No auto-resume. Route received feedback to local native replies with agent identity; status-only events authorize neither replies nor integration. Stop the watcher before UI/workspace cleanup. On-demand reads remain available.
- Use /agents and FleetView to inspect conversations, progress, and model availability. Model pins can fall back to the parent if unavailable; verify all four models, especially claude-code-cli/opus, before delegating. Child extensions are explicitly limited to command guards; nested delegation and built-in Git worktree isolation are disabled.
</delegation>
