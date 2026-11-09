# Legacy teardown

Read only for a dedicated Pi/tab created by an older feature workflow. Current activation adopts an existing coordinator and preserves it under [Cleanup](finishing.md#cleanup).

Before removing a legacy coordinator workspace, terminate its task-owned UI, watchers, children and Pi/tab. Independently verify termination from another conversation; another tab in the same Rex session is sufficient. Preserve the shared session and unrelated tabs.

Verify exact task ownership and ensure no live process cwd uses the workspace. Apply [Finishing](finishing.md)'s approval, recoverability and destination-specific completion gates before workspace or record deletion. Ambiguous ownership or exit evidence blocks teardown.
