"""Shared helpers for writing vault notes from external services.

The vault follows kepano's model (see the vault README): one note per thing,
classified with links. Entities live in ``References/``; their cover images go
in ``Attachments/``. These sync scripts are strictly *additive*: they create
notes that don't exist yet and append new occurrences (a watched date, an
owned-on date) to notes that do. They never rewrite a hand-curated note, so a
note's body and any manual frontmatter edits are always preserved.
"""

import os
import re
import urllib.request

# Obsidian forbids these in note/attachment filenames. Map the structural ones
# to a dash and drop the rest, then collapse whitespace — matching how the
# existing hand-made notes are named (e.g. "El Camino A Breaking Bad Movie").
_ILLEGAL = {
    "/": "-",
    "\\": "-",
    ":": " -",
}
_STRIP = str.maketrans("", "", '*?"<>|[]^#')


def sanitize(title):
    out = title
    for bad, good in _ILLEGAL.items():
        out = out.replace(bad, good)
    out = out.translate(_STRIP)
    out = re.sub(r"\s+", " ", out).strip()
    return out.rstrip(". ")


def fetch(url, headers=None):
    request = urllib.request.Request(method="GET", url=url, headers=headers or {})
    return urllib.request.urlopen(request).read()


def _frontmatter_lines(path):
    """Return the lines of a note's YAML frontmatter block (between the leading
    ``---`` fences), or ``None`` if the file has no frontmatter."""
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None
    return text[4 : end + 1].splitlines()


def index_by_field(references_dir, key):
    """Scan ``references_dir`` once and return ``{value: path}`` for every note
    carrying a scalar ``key: value`` in its frontmatter.

    This is the dedup index: every movie carries ``letterboxd:`` and every album
    carries ``discogs:``, so a note is matched by its source URL (trailing slash
    normalised away), never by filename. Building it once per run keeps the sync
    O(feed) instead of O(feed × vault).
    """
    needle = f"{key}: "
    index = {}
    for name in os.listdir(references_dir):
        if not name.endswith(".md"):
            continue
        path = os.path.join(references_dir, name)
        lines = _frontmatter_lines(path)
        if lines is None:
            continue
        for line in lines:
            if line.startswith(needle):
                index[line[len(needle) :].strip().rstrip("/")] = path
                break
    return index


def unique_note_path(references_dir, title, year):
    """Pick a filename for a new note: ``<title>.md``, disambiguated with a
    ``(year)`` suffix only if the plain name is already taken — the vault's
    "add a parenthetical only to disambiguate" rule."""
    base = sanitize(title)
    plain = os.path.join(references_dir, f"{base}.md")
    if not os.path.exists(plain):
        return plain, base
    disambig = sanitize(f"{title} ({year})")
    return os.path.join(references_dir, f"{disambig}.md"), disambig


def add_list_item(path, key, item):
    """Add ``- "item"`` to a note's multi-valued ``key:`` (e.g. a new watched
    date), if not already present. Handles all three frontmatter shapes the
    vault uses for such a key — a YAML list, an empty key, and the rare scalar
    ``key: "value"`` form (which is upgraded to a list so no value is lost).
    Returns True if the file changed."""
    quoted_item = f'"{item}"'
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines(keepends=True)

    if not lines or lines[0].rstrip("\n") != "---":
        return False
    fm_end = next(
        (i for i in range(1, len(lines)) if lines[i].rstrip("\n") == "---"), None
    )
    if fm_end is None:
        return False
    key_idx = next(
        (
            i
            for i in range(1, fm_end)
            if re.match(rf"^{re.escape(key)}:( |$)", lines[i].rstrip("\n"))
        ),
        None,
    )
    if key_idx is None:
        return False

    rest = lines[key_idx].rstrip("\n")[len(key) + 1 :].strip()
    if rest:
        # scalar form: upgrade to a list, keeping the existing value first
        if rest == quoted_item:
            return False
        lines[key_idx] = f"{key}:\n  - {rest}\n  - {quoted_item}\n"
    else:
        # list (or empty) form: dedup against existing "  - ..." items
        j = key_idx + 1
        already = set()
        while j < fm_end and lines[j].startswith("  - "):
            already.add(lines[j].strip())
            j += 1
        if f"- {quoted_item}" in already:
            return False
        lines.insert(j, f"  - {quoted_item}\n")

    with open(path, "w", encoding="utf-8") as f:
        f.write("".join(lines))
    return True


def set_scalar_if_empty(path, key, value):
    """Set ``key: value`` in frontmatter only if the key is currently empty
    (e.g. promote a wishlist album to owned by filling its blank ``lp:``).
    Returns True if the file changed."""
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines(keepends=True)
    if not lines or lines[0].rstrip("\n") != "---":
        return False
    fm_end = next(
        (i for i in range(1, len(lines)) if lines[i].rstrip("\n") == "---"), None
    )
    if fm_end is None:
        return False
    for i in range(1, fm_end):
        if lines[i].rstrip("\n") == f"{key}:":  # present but empty
            lines[i] = f"{key}: {value}\n"
            with open(path, "w", encoding="utf-8") as f:
                f.write("".join(lines))
            return True
    return False


def write_note(path, text):
    """Create a note. Never overwrites an existing file."""
    if os.path.exists(path):
        return False
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return True


def download(url, dest, headers=None):
    """Download ``url`` to ``dest`` unless it already exists."""
    if os.path.exists(dest):
        return
    data = fetch(url, headers=headers)
    with open(dest, "wb") as f:
        f.write(data)


def ensure_person_note(references_dir, name, type_link):
    """Create the thin People note a ``director``/``artist`` link points at, if
    it doesn't exist — so the Director/Artist Base views resolve. Mirrors the
    Director/Artist templates: categories [[People]] + a types link, with the
    matching embedded Base view in the body."""
    base = sanitize(name)
    path = os.path.join(references_dir, f"{base}.md")
    if os.path.exists(path):
        return
    section = "Movies" if type_link == "Directors" else "Albums"
    view = "Director" if type_link == "Directors" else "Artist"
    text = (
        "---\n"
        "categories:\n"
        '  - "[[People]]"\n'
        "types:\n"
        f'  - "[[{type_link}]]"\n'
        "---\n"
        f"## {section}\n\n"
        f"![[{section}.base#{view}]]\n"
    )
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
