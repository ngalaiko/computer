import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import discogs
import letterboxd


class ImporterTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.vault = Path(directory.name)
        templates = self.vault / "Templates"
        templates.mkdir()
        (templates / "Album Template.md").write_text(
            '---\ncategories:\n  - "[[Albums]]"\nlp:\n---\nAlbum notes.\n'
        )
        (templates / "Movie Template.md").write_text(
            '---\ncategories:\n  - "[[Movies]]"\nwatched:\n---\nMovie notes.\n'
        )
        for kind in ("Artist", "Director"):
            (templates / f"{kind} Template.md").write_text(
                f'---\ncategories:\n  - "[[{kind}s]]"\n---\nPerson notes.\n'
            )

    def http(self, responses):
        def respond(request):
            return io.BytesIO(responses[request.full_url])

        return patch("urllib.request.urlopen", side_effect=respond)

    def release(self, **fields):
        return {
            "basic_information": {"id": 1, "title": "Record", "year": 2020, **fields}
        }

    def run_discogs(self, collection=(), wants=()):
        responses = {
            "https://api.discogs.com/users/test/collection/folders/0/releases?sort=artist": json.dumps(
                {"releases": collection}
            ).encode(),
            "https://api.discogs.com/users/test/wants": json.dumps(
                {"wants": wants}
            ).encode(),
        }
        output = io.StringIO()
        with self.http(responses), contextlib.redirect_stdout(output):
            discogs.main("test", "token", str(self.vault), True)
        return output.getvalue()

    def run_letterboxd(self, entries, directors=()):
        items = "".join(
            f"<item><letterboxd:filmTitle>{title}</letterboxd:filmTitle>"
            f"<link>https://letterboxd.com/test/film/{slug}/</link>"
            "<letterboxd:filmYear>2020</letterboxd:filmYear>"
            f"<letterboxd:watchedDate>{date}</letterboxd:watchedDate></item>"
            for title, slug, date in entries
        )
        film = (
            '<script type="application/ld+json">'
            + json.dumps({"director": [{"name": name} for name in directors]})
            + "</script>"
        )
        responses = {
            "https://letterboxd.com/test/rss/": (
                '<rss xmlns:letterboxd="https://letterboxd.com"><channel>'
                + items
                + "</channel></rss>"
            ).encode(),
            **{
                f"https://letterboxd.com/film/{slug}/": film.encode()
                for _, slug, _ in entries
            },
        }
        output = io.StringIO()
        with self.http(responses), contextlib.redirect_stdout(output):
            letterboxd.main("test", str(self.vault))
        return output.getvalue()

    def test_repeated_film_creates_one_note_with_both_watched_dates(self):
        entries = [("Film", "film", "2025-03-02"), ("Film", "film", "2025-03-01")]
        output = self.run_letterboxd(entries)

        self.assertEqual(sorted(p.name for p in self.vault.glob("*.md")), ["Film.md"])
        path = self.vault / "Film.md"
        text = path.read_text()
        self.assertIn('watched:\n  - "[[2025-03-02]]"\n  - "[[2025-03-01]]"\n', text)
        self.assertTrue(text.endswith("---\nMovie notes.\n"))
        self.assertIn("letterboxd: 1 new, 1 updated", output)
        self.assertIn("letterboxd: 0 new, 0 updated", self.run_letterboxd(entries))
        self.assertEqual(path.read_text(), text)

    def test_title_collisions_preserve_handwritten_notes(self):
        for title in ("Record", "Film"):
            with self.subTest(importer=title):
                occupied = [
                    f"{title}.md",
                    f"{title} (2020).md",
                    f"{title} (2020) (2).md",
                ]
                for name in occupied:
                    (self.vault / name).write_text("Handwritten.\n")

                if title == "Record":
                    self.run_discogs(wants=[self.release()])
                    source = "discogs: https://www.discogs.com/release/1"
                else:
                    self.run_letterboxd([("Film", "film", "2025-03-01")])
                    source = "letterboxd: https://letterboxd.com/film/film/"

                created = self.vault / f"{title} (2020) (3).md"
                self.assertTrue(
                    created.exists(), "no note created beyond occupied filenames"
                )
                self.assertIn(source, created.read_text())
                for name in occupied:
                    self.assertEqual((self.vault / name).read_text(), "Handwritten.\n")

    def test_person_name_collision_imports_single_entry_without_changing_person(self):
        for title, kind in (("Record", "Artist"), ("Film", "Director")):
            with self.subTest(importer=title):
                if title == "Record":
                    release = self.release(artists=[{"name": "Record"}])
                    output = self.run_discogs(
                        collection=[{**release, "date_added": "2025-03-01T12:00:00"}]
                    )
                    expected_summary = "discogs: 1 new, 0 updated"
                    expected_source = "discogs: https://www.discogs.com/release/1"
                    expected_field = 'lp: "[[2025-03-01]]"'
                else:
                    output = self.run_letterboxd(
                        [
                            ("Film", "film", "2025-03-02"),
                        ],
                        directors=["Film"],
                    )
                    expected_summary = "letterboxd: 1 new, 0 updated"
                    expected_source = "letterboxd: https://letterboxd.com/film/film/"
                    expected_field = 'watched:\n  - "[[2025-03-02]]"'

                created = self.vault / f"{title} (2020).md"
                self.assertTrue(created.exists(), "single entry was not imported")
                self.assertIn(expected_field, created.read_text())
                self.assertIn(expected_source, created.read_text())
                person = self.vault / f"{title}.md"
                template = self.vault / "Templates" / f"{kind} Template.md"
                self.assertEqual(person.read_text(), template.read_text())
                self.assertIn(expected_summary, output)
                self.assertEqual(output.count("  new "), 1)

    def test_updates_publish_complete_notes_without_modifying_old_snapshots(self):
        backups = self.vault / "Backups"
        backups.mkdir()
        for title in ("Record", "Film"):
            with self.subTest(importer=title):
                if title == "Record":
                    old = (
                        "---\ndiscogs: https://www.discogs.com/release/1\n"
                        "lp: \n---\nMy album review.\n"
                    )
                    expected = old.replace("lp: \n", 'lp: "[[2025-03-01]]"\n')
                else:
                    old = (
                        "---\nletterboxd: https://letterboxd.com/film/film/\n"
                        'watched: "[[2025-02-01]]"\n---\nMy film review.\n'
                    )
                    expected = old.replace(
                        'watched: "[[2025-02-01]]"\n',
                        'watched:\n  - "[[2025-02-01]]"\n  - "[[2025-03-01]]"\n',
                    )
                path = self.vault / f"{title}.md"
                path.write_text(old)
                snapshot = backups / path.name
                os.link(path, snapshot)

                if title == "Record":
                    self.run_discogs(
                        collection=[{**self.release(), "date_added": "2025-03-01"}]
                    )
                else:
                    self.run_letterboxd([("Film", "film", "2025-03-01")])

                self.assertEqual(snapshot.read_text(), old)
                self.assertEqual(path.read_text(), expected)
                self.assertFalse(list(self.vault.glob(".*.tmp")))

    def test_wishlist_promotes_to_owned_without_changing_handwritten_content(self):
        self.run_discogs(wants=[self.release()])
        path = self.vault / "Record.md"
        wishlist = path.read_text().replace("Album notes.", "My review.\nlp: body only")
        path.write_text(wishlist)
        owned = {**self.release(), "date_added": "2025-03-01T12:00:00"}

        output = self.run_discogs(collection=[owned])

        expected = wishlist.replace("lp: \n", 'lp: "[[2025-03-01]]"\n')
        self.assertEqual(path.read_text(), expected)
        self.assertIn("discogs: 0 new, 1 updated", output)
        self.assertIn("discogs: 0 new, 0 updated", self.run_discogs(collection=[owned]))
        self.assertEqual(path.read_text(), expected)


if __name__ == "__main__":
    unittest.main()
