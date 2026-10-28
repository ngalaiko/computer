import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, copyFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import test from "node:test";

const configPath = new URL("./config.toml", import.meta.url);
const source = process.env.HUNK_SOURCE;

test(
  "native config resolver accepts every configured option and theme field",
  { skip: !source },
  async (t) => {
    const root = mkdtempSync(join(tmpdir(), "hunk-config-"));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    mkdirSync(join(root, "hunk"));
    copyFileSync(configPath, join(root, "hunk/config.toml"));
    const load = (path) =>
      import(pathToFileURL(join(source, "packages/hunk/src", path)).href);
    const { resolveConfiguredInput, CONFIG_REFERENCE_OPTIONS } =
      await load("core/run/config.ts");
    const { CUSTOM_THEME_COLOR_KEYS } = await load(
      "core/theme/customThemes.ts",
    );
    const { parseKeyChord } = await load("extension-api/keys.ts");
    const config = Bun.TOML.parse(await Bun.file(configPath).text());
    const result = resolveConfiguredInput(
      { kind: "vcs", options: {} },
      {
        cwd: root,
        env: { HOME: root, XDG_CONFIG_HOME: root },
      },
    );
    for (const [key, value] of Object.entries(config)) {
      if (key === "themes" || key === "extensions") continue;
      if (key === "keybindings") {
        assert.deepEqual(result.keybindings, value);
        continue;
      }
      const option = CONFIG_REFERENCE_OPTIONS.find(
        (option) => option.key === key,
      );
      assert.ok(option, `unsupported option ${key}`);
      assert.equal(result.input.options[option.property], value, key);
    }
    assert.deepEqual(result.keybindings["hunk.review.previousFile"], []);
    const theme = config.themes.zenwritten;
    const parsed = result.customThemes.find(
      (theme) => theme.id === "zenwritten",
    );
    assert.ok(parsed);
    for (const [key, value] of Object.entries(theme)) {
      if (["base", "label", "syntax_scopes"].includes(key)) continue;
      assert.ok(
        CUSTOM_THEME_COLOR_KEYS.includes(key),
        `unsupported theme field ${key}`,
      );
      assert.equal(parsed[key], value.toLowerCase(), key);
    }
    assert.deepEqual(
      parsed.syntaxScopes,
      Object.fromEntries(
        Object.entries(theme.syntax_scopes).map(([key, color]) => [
          key,
          color.toLowerCase(),
        ]),
      ),
    );
    assert.equal(result.startupNotices, undefined);
    assert.ok(parseKeyChord(",o").error, "native config cannot bind sequences");
    assert.equal(parseKeyChord("s").base, "s");
  },
);

test(
  "inherited Shiki colors stay neutral in Nix, TypeScript and JSON",
  { skip: !process.env.HUNK_SHIKI_MODULE },
  async () => {
    const { createHighlighter } = await import(process.env.HUNK_SHIKI_MODULE);
    const config = Bun.TOML.parse(await Bun.file(configPath).text()).themes
      .zenwritten;
    const highlighter = await createHighlighter({
      themes: [config.base],
      langs: ["nix", "typescript", "json"],
    });
    try {
      const base = highlighter.getTheme(config.base);
      await highlighter.loadTheme({
        ...base,
        name: "zenwritten-test",
        settings: [
          ...base.settings,
          ...Object.entries(config.syntax_scopes).map(
            ([scope, foreground]) => ({ scope, settings: { foreground } }),
          ),
        ],
      });
      const neutral = new Set([
        "#BBBBBB",
        "#686868",
        "#9E9E9E",
        "#8B8B8B",
        "#969696",
        "#939393",
      ]);
      for (const [lang, code] of [
        [
          "nix",
          '{ pkgs, ... }: let name = "hello"; in { value = 42; enabled = true; inherit name; } # comment',
        ],
        [
          "typescript",
          "const name: string = `hello ${value}`; function greet(user: User) { return user.name + 42; } // comment",
        ],
        [
          "json",
          '{ "name": "hello", "count": 42, "enabled": true, "nested": null }',
        ],
      ]) {
        const { tokens } = highlighter.codeToTokens(code, {
          lang,
          theme: "zenwritten-test",
        });
        for (const token of tokens.flat()) {
          if (!token.content.trim()) continue;
          assert.ok(
            neutral.has(token.color.toUpperCase()),
            `${lang} ${JSON.stringify(token.content)}: ${token.color}`,
          );
        }
        for (const word of ["hello", "42"]) {
          const token = tokens
            .flat()
            .find((token) => token.content.includes(word));
          assert.ok(token, `${lang}: ${word}`);
          assert.equal(
            token.color.toUpperCase(),
            "#8B8B8B",
            `${lang}: ${word}`,
          );
        }
      }
    } finally {
      highlighter.dispose();
    }
  },
);
