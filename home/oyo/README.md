# Activation

Before approved Home Manager activation, back up unmanaged `~/.config/oyo/config.toml`, `themes/zenwritten.json` and `themes/zenwritten.tmTheme`; do not force-overwrite them.

Preserve `~/.local/state/hunk` and all Oyo review databases. Thread history is not converted.

Homebrew cleanup removes Hunk on activation. Defer activation until the operator decides how to handle existing Hunk sessions; never terminate unrelated sessions.
