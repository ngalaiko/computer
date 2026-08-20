#!/usr/bin/env python3
"""Sync Letterboxd diary entries into the vault as Movie notes.

For each film in the public RSS feed:
  * if a note already carries its ``letterboxd:`` URL, append the new watched
    date to that note's ``watched:`` list (nothing else is touched);
  * otherwise create a new Movie note, scraping the film page's JSON-LD for the
    director(s), downloading the poster into Attachments/, and creating any
    missing Director notes.

The feed only carries the most recent ~50 entries, which is exactly what an
ongoing sync needs; the historical backfill already lives in the vault. TV
entries are treated like films (Letterboxd logs them the same way, and their
page still exposes a director), so they become ordinary Movie notes too.
"""

import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime

import vaultlib

NS = {"letterboxd": "https://letterboxd.com", "tmdb": "https://themoviedb.org"}
UA = "vault-sync robot"
HEADERS = {"User-Agent": UA}


def parse_feed(body):
    root = ET.fromstring(body)
    for item in root.findall(".//item"):
        title_el = item.find("letterboxd:filmTitle", NS)
        link = item.findtext("link")
        if title_el is None or not link:
            continue
        slug_match = re.search(r"/film/([^/]+)", link)
        if not slug_match:
            continue
        watched_el = item.find("letterboxd:watchedDate", NS)
        if watched_el is None:
            continue  # a rating/review without a diary date — skip
        poster = None
        desc = item.findtext("description") or ""
        img = re.search(r'<img\s+src="([^"]+)"', desc)
        if img:
            # request the larger crop letterboxd also serves
            poster = img.group(1).replace("0-230-0-345", "0-600-0-900")
        year_el = item.find("letterboxd:filmYear", NS)
        yield {
            "title": title_el.text,
            "slug": slug_match.group(1),
            "url": f"https://letterboxd.com/film/{slug_match.group(1)}/",
            "year": year_el.text if year_el is not None else "",
            "watched": watched_el.text,  # YYYY-MM-DD
            "liked": item.findtext("letterboxd:memberLike", default="No", namespaces=NS)
            == "Yes",
            "poster": poster,
        }


def scrape_directors(film_url):
    """Pull director name(s) from the film page's schema.org JSON-LD."""
    try:
        html = vaultlib.fetch(film_url, headers=HEADERS).decode("utf-8", "replace")
    except Exception as e:  # network hiccup — create the note without directors
        print(f"  war: could not fetch {film_url}: {e}", file=sys.stderr)
        return []
    m = re.search(
        r'<script type="application/ld\+json">(.*?)</script>', html, re.DOTALL
    )
    if not m:
        return []
    blob = m.group(1)
    blob = re.sub(
        r"/\*.*?\*/", "", blob, flags=re.DOTALL
    ).strip()  # strip CDATA comments
    try:
        data = json.loads(blob)
    except json.JSONDecodeError:
        return []
    return [d["name"] for d in data.get("director", []) if d.get("name")]


def movie_note(title, year, poster_file, directors, url, liked, watched):
    directors_block = "director:\n" + "".join(f'  - "[[{d}]]"\n' for d in directors)
    cover_line = f'cover: "[[{poster_file}]]"\n' if poster_file else "cover:\n"
    return (
        "---\n"
        "categories:\n"
        '  - "[[Movies]]"\n'
        f"{cover_line}"
        f"{directors_block}"
        f"letterboxd: {url}\n"
        f"liked: {'true' if liked else 'false'}\n"
        "watched:\n"
        f'  - "[[{watched}]]"\n'
        f"year: {year}\n"
        "---\n"
    )


def main(username, vault):
    notes = vault
    attachments = os.path.join(vault, "Attachments")
    os.makedirs(notes, exist_ok=True)
    os.makedirs(attachments, exist_ok=True)

    feed = vaultlib.fetch(f"https://letterboxd.com/{username}/rss/", headers=HEADERS)
    index = vaultlib.index_by_field(notes, "letterboxd")

    created = updated = 0
    for entry in parse_feed(feed):
        existing = index.get(entry["url"].rstrip("/"))
        if existing:
            if vaultlib.add_list_item(existing, "watched", f"[[{entry['watched']}]]"):
                updated += 1
                print(f"  + watched {entry['watched']}: {os.path.basename(existing)}")
            continue

        path, base = vaultlib.unique_note_path(notes, entry["title"], entry["year"])

        poster_file = None
        if entry["poster"]:
            ext = os.path.splitext(entry["poster"].split("?")[0])[1] or ".jpg"
            poster_file = f"{base}{ext}"
            try:
                vaultlib.download(
                    entry["poster"], os.path.join(attachments, poster_file), HEADERS
                )
            except Exception as e:
                print(
                    f"  war: poster download failed for {entry['title']}: {e}",
                    file=sys.stderr,
                )
                poster_file = None

        directors = scrape_directors(entry["url"])
        for d in directors:
            vaultlib.ensure_person_note(notes, d, "Directors")

        vaultlib.write_note(
            path,
            movie_note(
                entry["title"],
                entry["year"],
                poster_file,
                directors,
                entry["url"],
                entry["liked"],
                entry["watched"],
            ),
        )
        created += 1
        print(
            f"  new movie: {os.path.basename(path)}  (dir: {', '.join(directors) or '?'})"
        )

    print(f"letterboxd: {created} new, {updated} updated")


if __name__ == "__main__":
    p = argparse.ArgumentParser(
        description="Sync Letterboxd diary into vault Movie notes."
    )
    p.add_argument(
        "-u", "--username", default=os.environ.get("LETTERBOXD_USERNAME", "ngalaiko")
    )
    p.add_argument(
        "--vault",
        default=os.environ.get("OBSIDIAN_VAULT_DIR", "/var/lib/assistant/Vault"),
    )
    args = p.parse_args()
    main(args.username, args.vault)
