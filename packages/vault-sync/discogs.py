#!/usr/bin/env python3
"""Sync a Discogs collection + wantlist into the vault as Album notes.

The vault's convention (see the Albums memory / README): one note per album,
``categories: [[Albums]]``, an ``lp:`` date meaning "owned on vinyl" — empty for
a wishlist record. So:
  * every release in the Discogs collection  -> Album note, lp = date added;
  * every release in the wantlist not owned   -> Album note, lp empty (wishlist).

Dedup is by the ``discogs:`` release URL, which every existing album carries.
A wishlist note whose record you later buy gets its blank ``lp:`` filled in
(the only mutation); nothing else about a hand-curated note is touched.
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.request
from urllib.parse import urljoin

import vaultlib

BASE_URL = "https://api.discogs.com"
UA = "vault-sync robot"


def api_get(url, token):
    headers = {"User-Agent": UA, "Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Discogs token={token}"
    while True:
        req = urllib.request.Request(method="GET", url=url, headers=headers)
        try:
            resp = urllib.request.urlopen(req)
        except urllib.error.HTTPError as e:
            if e.code == 429:  # rate limited
                time.sleep(int(e.headers.get("Retry-After", 2)))
                continue
            raise
        return json.loads(resp.read())


def paginate(first_url, token, key):
    url = first_url
    while url:
        page = api_get(url, token)
        for item in page.get(key, []):
            yield item
        url = page.get("pagination", {}).get("urls", {}).get("next")
        time.sleep(1)  # stay under Discogs' rate limit


_ARTIST_SUFFIX = re.compile(r"\s*\(\d+\)$")  # Discogs disambiguator, e.g. "Nirvana (2)"


def clean_artist(name):
    return _ARTIST_SUFFIX.sub("", name).strip()


def release_url(info):
    return f"https://www.discogs.com/release/{info['id']}"


def album_note(title, year, artists, cover_file, url, lp_date):
    artist_block = "artist:\n" + "".join(f'  - "[[{a}]]"\n' for a in artists)
    cover_line = f'cover: "[[{cover_file}]]"\n' if cover_file else "cover:\n"
    lp_line = f'lp: "[[{lp_date}]]"\n' if lp_date else "lp:\n"
    return (
        "---\n"
        "categories:\n"
        '  - "[[Albums]]"\n'
        f"{artist_block}"
        f"{cover_line}"
        f"discogs: {url}\n"
        f"{lp_line}"
        f"year: {year}\n"
        "---\n"
    )


def sync_release(item, references, attachments, token, lp_date, index):
    """Create or update a single album note. ``lp_date`` is the owned-on date
    (collection) or None (wantlist). ``index`` is the {discogs-url: path} dedup
    map, updated in place when a note is created. Returns 'new', 'updated', or
    None."""
    info = item["basic_information"]
    url = release_url(info)
    title = info["title"]
    year = info.get("year") or ""
    artists = [
        clean_artist(a["name"]) for a in info.get("artists", []) if a.get("name")
    ]

    existing = index.get(url.rstrip("/"))
    if existing:
        if lp_date and vaultlib.set_scalar_if_empty(existing, "lp", f'"[[{lp_date}]]"'):
            print(f"  + owned {lp_date}: {os.path.basename(existing)}")
            return "updated"
        return None

    path, base = vaultlib.unique_note_path(references, title, year)

    cover_file = None
    cover = info.get("cover_image")
    if cover and "spacer" not in os.path.basename(cover):
        ext = os.path.splitext(cover.split("?")[0])[1] or ".jpeg"
        cover_file = f"{base}{ext}"
        try:
            vaultlib.download(
                cover,
                os.path.join(attachments, cover_file),
                {"User-Agent": UA, "Authorization": f"Discogs token={token}"},
            )
        except Exception as e:
            print(f"  war: cover download failed for {title}: {e}", file=sys.stderr)
            cover_file = None

    for a in artists:
        vaultlib.ensure_person_note(references, a, "Artists")

    vaultlib.write_note(
        path, album_note(title, year, artists, cover_file, url, lp_date)
    )
    index[url.rstrip("/")] = path
    kind = "owned" if lp_date else "wishlist"
    print(f"  new album ({kind}): {os.path.basename(path)}  ({', '.join(artists)})")
    return "new"


def main(username, token, vault, include_wantlist):
    notes = vault
    attachments = os.path.join(vault, "Attachments")
    os.makedirs(notes, exist_ok=True)
    os.makedirs(attachments, exist_ok=True)

    index = vaultlib.index_by_field(notes, "discogs")
    created = updated = 0

    collection = urljoin(
        BASE_URL, f"/users/{username}/collection/folders/0/releases?sort=artist"
    )
    for item in paginate(collection, token, "releases"):
        date_added = (item.get("date_added") or "")[:10]  # ISO ts -> YYYY-MM-DD
        result = sync_release(
            item, notes, attachments, token, date_added or None, index
        )
        created += result == "new"
        updated += result == "updated"

    if include_wantlist:
        wantlist = urljoin(BASE_URL, f"/users/{username}/wants")
        for item in paginate(wantlist, token, "wants"):
            result = sync_release(item, notes, attachments, token, None, index)
            created += result == "new"

    print(f"discogs: {created} new, {updated} updated")


if __name__ == "__main__":
    p = argparse.ArgumentParser(
        description="Sync Discogs collection + wantlist into vault Album notes."
    )
    p.add_argument(
        "-u", "--username", default=os.environ.get("DISCOGS_USERNAME", "ngalaiko")
    )
    p.add_argument("-t", "--token", default=os.environ.get("DISCOGS_TOKEN"))
    p.add_argument(
        "--vault",
        default=os.environ.get("OBSIDIAN_VAULT_DIR", "/var/lib/assistant/Vault"),
    )
    p.add_argument(
        "--no-wantlist",
        dest="wantlist",
        action="store_false",
        help="skip the wantlist (owned records only)",
    )
    args = p.parse_args()
    if not args.token:
        sys.exit("discogs: no token (set DISCOGS_TOKEN or pass --token)")
    main(args.username, args.token, args.vault, args.wantlist)
