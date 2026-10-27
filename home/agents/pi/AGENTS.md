<delegation>
Parent Pi sessions only. Child agents follow their assigned role instead.
- Delegate without asking when independent implementation, bounded edits, or substantive review justify the overhead. Use worker, small-worker, and reviewer respectively. Supply paths, requirements, and acceptance criteria.
- Before each writer launch, create a unique JJ workspace from the source working-copy change (`jj --config git.colocate=false workspace add --name <unique-name> -r @ <absolute-path>`). Keep workspaces under ~/.pi/agent/jj-workspaces/. Pass its absolute path as subagent cwd; preserve the source-relative subdirectory when applicable. Use worktree: false.
- Review a writer's workspace with reviewer cwd and supply its `jj diff`. The parent runs review test commands. Integration and workspace deletion require explicit operator approval.
- Launch subagents asynchronously, continue independent work, and let completion notifications resume the parent. Use status or /subagents-fleet to inspect progress; use bg_wait only when waiting is explicitly requested.
</delegation>
