# computer

Nix configuration for my Mac and remote [exe.dev](https://exe.dev) machine.

- `hosts/macbook`: nix-darwin configuration.
- `hosts/exedev`: NixOS configuration and user accounts.
- `home`: Home Manager configuration.
- `modules`, `packages`, `scripts`: shared modules, packages, and deployment tools.

```sh
darwin-rebuild switch --flake .#macbook # Apply Mac configuration
nix run .#deploy                      # Deploy to exedev over Tailscale
nix fmt                               # Format
nix flake check                       # Check
```

## Rex on the cloud machine

The `rex-login-server` service accepts the Tailscale principal
`ngalaiko@github` as the Linux account `nikita`. On the Mac, with Tailscale
connected, choose **Add Remote Host…** in Rex and enter
`http://nikita@exedev.tail4fad0.ts.net:7297`. Tailscale encrypts the connection;
this listener is separate from the public Funnel on port 443.

Rex's snapshot packages currently require a package token. Provision
`/etc/nix/rex.netrc` outside this repository, owned by root with mode `0600`,
containing `machine pkgs.superlogical.com login rex password YOUR_TOKEN`.
The cloud Nix configuration uses that file and includes it in the existing
encrypted restic backups, restored to the same path on a fresh disk.
The machine fetching the flake
inputs also needs authentication before the first deployment; for example,
use `sudo nix flake lock --option netrc-file /etc/nix/rex.netrc` from a checkout
on the cloud machine to add the Rex input to `flake.lock`. Keep the token out
of the repository and command-line arguments. Later, `nix flake update rex`
selects a newer snapshot.

## Skills

`agents.skills` declares shared skills in `~/.agents/skills`. Pi and Codex discover
that directory; Claude receives links through its Home Manager module. Encore
skills are declared in `hosts/macbook/encore.nix` and override Matt Pocock skills
with the same name. Update Matt Pocock's pinned revision in `flake.nix`, then run
`nix flake update mattpocock-skills`.

Harness-specific skills stay in `~/.pi/agent/skills`, `~/.claude/skills`, or
`~/.codex/skills`. Use `agents.pi.skills`, `programs.claude-code.skills`, or
`programs.codex.skills` for those. Claude connector skills remain Claude-only.

## Pi

Pi is installed through Homebrew. Version 1.4.0 supports native MCP. Its Zenwritten
Dark theme matches Neovim's palette. Upgrade existing installations with
`brew upgrade pi-coding-agent`, then apply the Mac configuration above.

Run `pi`, `/login`, and select OpenAI Codex. The default is `gpt-6.1-sol` with
medium reasoning; `/model` switches providers and models. Credentials stay in
`~/.pi/agent/auth.json`, outside Nix.

The baseline includes global instructions, git/push command guards, shared skills,
`agent-browser`, DuckDuckGo Lite search, and Plain MCP. Pi does not load Claude's skill folders.

`agent-browser` is installed through Homebrew. Run `agent-browser install` once to
download its browser. Its Pi skill loads instructions from the installed CLI.
The `web-search` skill queries DuckDuckGo Lite through Python's standard library;
search needs no browser, API key, or MCP server. DuckDuckGo can throttle requests
or return a bot challenge; the script reports these as failures.

Authenticate Plain with `pi mcp login plain`. Pi stores its own MCP credentials; Claude and
Codex sign-ins are not copied. Settings remain writable; activation merges the
managed defaults while preserving other fields.

Claude hooks and Codex prefix rules become a Pi `tool_call` extension. It blocks
direct `git` and `jj git push` commands, including chained commands. These pattern
checks are not a shell sandbox; wrappers and scripts can bypass them. Pi has no
equivalent of Codex's approval reviewer or filesystem sandbox.

Dash0's agent tracing plugin supports Claude, Codex, Cursor, and Copilot, but not
Pi. Its Claude hooks and setup commands are not loaded. The Dash0 CLI remains
available. Rust LSP integration, Codex app tools, desktop preferences, and session
history have no direct Pi equivalent. Claude and Codex remain available as
fallbacks.

Ghostty supports Pi's keyboard protocol without extra mappings. Use `/model` to
switch models, `Shift+Tab` for reasoning, `Enter` to steer, `Alt+Enter` to queue,
`/tree` to revisit a branch, and `pi --continue` to resume. Sessions and automatic
compaction are built in; additional workflow extensions are optional.

Sources: [Pi configuration](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/settings.md),
[MCP](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/mcp.md),
[extensions](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md),
[browser](https://agent-browser.dev/),
[Dash0 runtimes](https://github.com/dash0hq/dash0-agent-plugin).
