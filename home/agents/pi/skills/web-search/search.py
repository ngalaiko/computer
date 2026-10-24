import argparse
from html.parser import HTMLParser
import json
import sys
from urllib.error import URLError
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import Request, urlopen


class Results(HTMLParser):
    def __init__(self):
        super().__init__()
        self.results = []
        self.field = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        classes = attrs.get("class", "").split()
        if tag == "a" and "result-link" in classes:
            url = attrs.get("href", "")
            url = parse_qs(urlsplit(url).query).get("uddg", [url])[0]
            if urlsplit(url).scheme in ("http", "https"):
                self.results.append({"title": "", "url": url, "snippet": ""})
                self.field = "title"
        elif tag == "td" and "result-snippet" in classes and self.results:
            self.field = "snippet"

    def handle_data(self, data):
        if self.field:
            self.results[-1][self.field] += data

    def handle_endtag(self, tag):
        if (tag == "a" and self.field == "title") or (
            tag == "td" and self.field == "snippet"
        ):
            self.field = None


def parse_results(html):
    if any(marker in html.lower() for marker in ("challenge-form", "anomaly.js")):
        raise ValueError("DuckDuckGo returned a bot challenge; retry later.")
    parser = Results()
    parser.feed(html)
    if not parser.results and "no results found" not in html.lower():
        raise ValueError("DuckDuckGo returned an unrecognized search page.")
    return [
        {key: " ".join(value.split()) for key, value in result.items()}
        for result in parser.results
    ]


def main():
    parser = argparse.ArgumentParser(description="Search DuckDuckGo Lite.")
    parser.add_argument("query")
    parser.add_argument("-n", type=int, choices=range(1, 11), default=5)
    args = parser.parse_args()
    url = "https://lite.duckduckgo.com/lite/?" + urlencode({"q": args.query})
    request = Request(url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urlopen(request, timeout=20) as response:
            results = parse_results(response.read().decode("utf-8"))
        print(json.dumps(results[: args.n], ensure_ascii=False, indent=2))
    except (URLError, ValueError) as error:
        print(f"Search failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
