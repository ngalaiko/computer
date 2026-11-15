# Assistant calendar

Nix package for the existing CalDAV CLI, restored after removal of the old
assistant devShell left the documented calendar launcher without its executable.
The bundled `calendar.py` was recovered from the agent-owned `managing-calendar`
skill on exedev on 2026-11-15; only formatting has changed. Its source is now
versioned here, with dependencies pinned by the repository's `flake.lock`.

The package selects CalDAV's supported `requests` fallback backend. The pinned
default `niquests` chain fails three upstream `urllib3-future` TLS/gzip tests;
this selection avoids that chain without disabling dependency tests. CalDAV's
own tests remain enabled. The installed script is named `assistant_calendar.py`
so it does not shadow Python's standard-library `calendar` module.

Build and run local smoke checks with `nix build .#assistant-calendar`. The Amp
account installs the package; its existing `icloud-calendar` launcher continues
to load private runtime settings before invoking it. No home configuration,
credentials, calendars, or services are managed by this package.

The CLI reads `ICLOUD_ACCOUNT`, an absolute `ASSISTANT_SECRETS_FILE`, and the SOPS
age configuration from the runtime environment. Credentials are decrypted directly
in the consumer process, not passed as arguments or printed. Calendar discovery
and bounded reads use CalDAV; writes require explicit authorization, stable UIDs,
and conditional requests. Recurring and invitation-bearing existing events remain
read-only. `--help` requires neither credentials nor a network connection.
