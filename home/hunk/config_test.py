import pathlib
import tomllib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class NativeConfig(unittest.TestCase):
    def setUp(self):
        self.config = tomllib.loads((ROOT / "home/hunk/config.toml").read_text())
        self.theme = self.config["themes"]["zenwritten"]

    def test_runtime(self):
        for key, value in {
            "theme": "zenwritten",
            "vcs": "jj",
            "agent_notes": True,
            "watch": True,
            "mode": "unified",
            "menu_bar": False,
            "prompt_save_view_preferences": False,
        }.items():
            self.assertEqual(self.config[key], value, key)

    def test_explicit_global_extension_path(self):
        self.assertEqual(
            self.config.get("keybindings"), {"hunk.review.previousFile": []}
        )
        self.assertEqual(
            self.config["extensions"]["paths"],
            ["~/.config/hunk/extensions/pi-review"],
        )

    def test_palette(self):
        for key, color in {
            "background": "#191919",
            "text": "#BBBBBB",
            "muted": "#686868",
            "panel": "#222222",
            "border": "#404040",
            "selectedHunk": "#404040",
            "lineNumberFg": "#616161",
            "addedBg": "#232D1A",
            "removedBg": "#3E2225",
            "fileModified": "#6099C0",
            "addedSignColor": "#819B69",
            "removedSignColor": "#DE6E7C",
        }.items():
            self.assertEqual(self.theme[key], color, key)
        self.assertIn("#1D2C36", self.theme.values())
        for color in ["#B77E64", "#B279A7", "#66A5AD"]:
            self.assertIn(color, self.theme.values())

    def test_narrow_base_selectors_are_neutralized(self):
        scopes = self.theme["syntax_scopes"]
        for scope, color in {
            "source": "#BBBBBB",
            "comment": "#686868",
            "variable": "#9E9E9E",
            "string": "#8B8B8B",
            "constant.numeric": "#8B8B8B",
            "entity.name.type": "#969696",
            "keyword": "#939393",
            "string.quoted": "#8B8B8B",
            "string.template": "#8B8B8B",
            "support.type.property-name.json": "#9E9E9E",
            "variable.other.constant": "#9E9E9E",
            "support.function.node": "#9E9E9E",
            "keyword.operator.accessor": "#939393",
            "punctuation.definition.template-expression": "#939393",
        }.items():
            self.assertEqual(scopes[scope], color, scope)
        for color in scopes.values():
            self.assertIn(
                color,
                {"#BBBBBB", "#686868", "#9E9E9E", "#8B8B8B", "#969696", "#939393"},
            )

    def test_home_manager_imports_and_deploys_native_config(self):
        self.assertIn("./hunk", (ROOT / "home/default.nix").read_text())
        module = (ROOT / "home/hunk/default.nix").read_text()
        self.assertIn('"hunk/config.toml".source = ./config.toml;', module)
        self.assertIn('"hunk/extensions/pi-review".source = ./review;', module)
        brew = (ROOT / "hosts/macbook/homebrew.nix").read_text()
        self.assertIn('"hunk"', brew)


if __name__ == "__main__":
    unittest.main()
