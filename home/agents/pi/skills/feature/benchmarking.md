# Optional benchmarking

Read only when the operator requests workflow/model benchmarking. Record delegated model, elapsed time, retries and coordinator corrections at `~/.pi/agent/finishing-trials/<task-key>.jsonl`, outside task workspaces. Include token/cost data only when automatically available; otherwise mark unknown.

These records survive task cleanup. Exclude them from cleanup manifests. Benchmarking does not replace verification evidence or alter approval gates.
