---
name: web-search
description: Search the web for documentation, current facts, or sources using DuckDuckGo Lite without a browser or API key.
---

Run `python3 <skill-directory>/search.py "query"` using this skill's directory.
Use `-n 10` for more results. Output contains titles, URLs, and snippets.

Read relevant source pages before relying on snippets. Use `agent-browser` when
a page needs rendering or interaction. Cite source URLs in the response.

A challenge or throttle is a failed search, not an empty result. Report it and
respect any retry delay.
