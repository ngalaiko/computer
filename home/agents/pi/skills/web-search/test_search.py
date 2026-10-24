import unittest

from search import parse_results


class SearchTests(unittest.TestCase):
    def test_results(self):
        html = """
        <a class="result-link" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fpi.dev%2F">
          Pi &amp; tools
        </a>
        <td class="result-snippet">An <b>agent</b> for coding.</td>
        <a class="result-link" href="https://example.org/">Other</a>
        <td class="result-snippet">Another result.</td>
        """
        self.assertEqual(
            parse_results(html),
            [
                {
                    "title": "Pi & tools",
                    "url": "https://pi.dev/",
                    "snippet": "An agent for coding.",
                },
                {
                    "title": "Other",
                    "url": "https://example.org/",
                    "snippet": "Another result.",
                },
            ],
        )

    def test_empty_results(self):
        self.assertEqual(parse_results("<p>No results found</p>"), [])

    def test_challenge(self):
        with self.assertRaisesRegex(ValueError, "bot challenge"):
            parse_results('<form id="challenge-form"></form>')

    def test_unrecognized_page(self):
        with self.assertRaisesRegex(ValueError, "unrecognized"):
            parse_results("<p>Service unavailable</p>")


if __name__ == "__main__":
    unittest.main()
