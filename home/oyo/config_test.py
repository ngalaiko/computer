import json
import pathlib
import plistlib
import tomllib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
OYO = ROOT / "home/oyo"


class OyoConfig(unittest.TestCase):
    def test_native_config(self):
        config = tomllib.loads((OYO / "config.toml").read_text())
        self.assertEqual(
            config,
            {
                "ui": {
                    "view_mode": "unified",
                    "watch": True,
                    "topbar": False,
                    "confirm_quit": False,
                    "theme": {"name": "zenwritten", "mode": "dark"},
                    "syntax": {"mode": "on", "theme": "zenwritten"},
                }
            },
        )

    def test_complete_native_palette(self):
        document = json.loads((OYO / "zenwritten.json").read_text())
        theme = {
            k: {"dark": document["defs"].get(v["dark"], v["dark"])}
            for k, v in document["theme"].items()
        }
        expected = {
            "text": "#BBBBBB",
            "textMuted": "#686868",
            "primary": "#6099C0",
            "secondary": "#9E9E9E",
            "accent": "#B8D8E0",
            "error": "#DE6E7C",
            "warning": "#B77E64",
            "success": "#819B69",
            "info": "#66A5AD",
            "background": "#191919",
            "backgroundPanel": "#222222",
            "backgroundElement": "#304654",
            "border": "#404040",
            "borderActive": "#6099C0",
            "borderSubtle": "#2A2A2A",
            "diffAdded": "#819B69",
            "diffAddedBg": "#232D1A",
            "diffRemoved": "#DE6E7C",
            "diffRemovedBg": "#3E2225",
            "diffContext": "#939393",
            "diffLineNumber": "#616161",
            "diffExtMarker": "#6099C0",
            "diffModifiedBg": "#1D2C36",
        }
        self.assertEqual(theme, {k: {"dark": v} for k, v in expected.items()})

    def test_file_tree_focus_contrast(self):
        document = json.loads((OYO / "zenwritten.json").read_text())
        theme = {
            k: document["defs"].get(v["dark"], v["dark"])
            for k, v in document["theme"].items()
        }

        def luminance(color):
            channels = [int(color[i : i + 2], 16) / 255 for i in (1, 3, 5)]
            linear = [
                c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
                for c in channels
            ]
            return sum(
                c * weight for c, weight in zip(linear, (0.2126, 0.7152, 0.0722))
            )

        def contrast(first, second):
            light, dark = sorted((luminance(first), luminance(second)), reverse=True)
            return (light + 0.05) / (dark + 0.05)

        self.assertGreaterEqual(
            contrast(theme["backgroundElement"], theme["backgroundPanel"]), 1.6
        )
        for foreground in ("accent", "text"):
            self.assertGreaterEqual(
                contrast(theme[foreground], theme["backgroundElement"]), 4.5
            )
        for indicator in ("diffAdded", "diffRemoved"):
            self.assertGreaterEqual(
                contrast(theme[indicator], theme["backgroundElement"]), 3.0
            )

    def test_textmate_syntax(self):
        theme = plistlib.loads((OYO / "zenwritten.tmTheme").read_bytes())
        self.assertEqual(theme["name"], "Zenwritten")
        self.assertEqual(theme["settings"][0]["settings"]["foreground"], "#BBBBBB")
        scopes = {
            scope.strip(): item["settings"]
            for item in theme["settings"][1:]
            for scope in item["scope"].split(",")
        }
        for scope, color in {
            "comment": "#686868",
            "variable": "#9E9E9E",
            "string": "#8B8B8B",
            "constant.numeric": "#8B8B8B",
            "entity.name.type": "#969696",
            "keyword": "#BBBBBB",
            "entity.name.function": "#BBBBBB",
            "punctuation": "#939393",
            "invalid": "#DE6E7C",
        }.items():
            self.assertEqual(scopes[scope]["foreground"], color)
        self.assertEqual(scopes["comment"]["fontStyle"], "italic")
        self.assertEqual(scopes["string"]["fontStyle"], "italic")
        self.assertEqual(scopes["keyword"]["fontStyle"], "bold")

    def test_deployment_and_retirement(self):
        self.assertIn("./oyo", (ROOT / "home/default.nix").read_text())
        module = (OYO / "default.nix").read_text()
        for target, source in {
            "oyo/config.toml": "config.toml",
            "oyo/themes/zenwritten.json": "zenwritten.json",
            "oyo/themes/zenwritten.tmTheme": "zenwritten.tmTheme",
        }.items():
            self.assertIn(f'"{target}".source = ./{source};', module)
        brew = (ROOT / "hosts/macbook/homebrew.nix").read_text()
        self.assertIn('"ahkohd/oyo"', brew)
        self.assertIn('"ahkohd/oyo/oy"', brew)
        self.assertFalse((ROOT / "home/hunk").exists())
        self.assertFalse((ROOT / "home/agents/pi/skills/hunk-review").exists())
        for file in ["home/default.nix", "home/agents/pi.nix", "flake.nix"]:
            text = (ROOT / file).read_text()
            self.assertNotIn("hunk", text)
            self.assertNotRegex(text, r"npm:[^\s\"]*pi-oyo")


if __name__ == "__main__":
    unittest.main()
