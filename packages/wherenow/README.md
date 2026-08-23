## wherenow

Self-hosted backend for [Where Now?](https://apps.apple.com/se/app/where-now/id6757414541?l=en-GB),
an iOS app for tracking where you've been.

Instead of a database, wherenow writes each position straight into an
[Obsidian](https://obsidian.md) vault as one markdown note, so the points show
up in the daily note they belong to (and on a map). It runs as a service next to
the vault on my [computer](https://github.com/ngalaiko/computer) box.

### Storage

Each `upload` position becomes a note in the vault root, rendered from the
vault's `Templates/Position Template.md` and identified by its UUID `id:` — there
is no other state, the notes _are_ the database. The template owns the
front-matter shape; wherenow only fills the `{{date}}`, `{{time}}`, `{{lat}}`,
`{{lon}}` and `{{id}}` placeholders and appends the free-text note as the body:

```
---
categories:
  - "[[Positions]]"
date: "[[2026-01-01]]"
time: 2026-01-01T13:00:00
location:
  - "59.33"
  - "18.07"
id: 0b5e…-…-…
---

free-text note, if any
```

Notes are named `YYYY-MM-DD HHMM.md` in local time (a ` (<shortid>)` suffix
disambiguates two points in the same minute, and keeps wherenow from ever
clobbering another note that already owns that name).

### API

All endpoints except `GET /api/?ping=1` require a `Bearer` token in the
`Authorization` header (the `TOKEN` env var).

```
GET    /api/?ping=1      # unauthenticated health check
GET    /api/?ping=auth   # authenticated health check
GET    /api/             # up to 200 most-recent positions (?limit=N, max 200)
POST   /api/             # {"id","lat","lon","timestamp","note","reason":"upload"}
PATCH  /api/             # {"id","note"} — updates the note body
DELETE /api/             # {"id"} — removes the note
```

Only `reason:"upload"` points are stored. `label`, `category` and `accuracy` are
accepted (for app compatibility) but not written to the notes. `GET` reconstructs
entries from the notes (timestamps rebuilt from the local time + `--tz`).

### Running

```
TOKEN=<bearer> wherenow --vault-dir=/path/to/Vault --tz=Europe/Stockholm
```

| flag / env    | default                                      | meaning                                                  |
| ------------- | -------------------------------------------- | -------------------------------------------------------- |
| `--vault-dir` | —                                            | vault the notes live in (**required**)                   |
| `--tz`        | `Local`                                      | IANA zone for note dates/times (tz database is embedded) |
| `--template`  | `<vault-dir>/Templates/Position Template.md` | note template to fill                                    |
| `TOKEN` (env) | —                                            | bearer token; **required**                               |
| `PORT` (env)  | `8080`                                       | listen port                                              |

Built with Nix from `packages/wherenow` in the
[computer](https://github.com/ngalaiko/computer) flake (an `s6` service behind a
path-routed ingress; see `hosts/exedev/users/assistant.nix`).
