{
  # Whole-tree formatter. `nix fmt` formats; `nix flake check` verifies (see the
  # `formatting` check in flake.nix). Add a language by enabling its program here.
  projectRootFile = "flake.nix";

  programs = {
    nixfmt.enable = true; # nix
    deadnix.enable = true; # unused nix bindings
    statix.enable = true; # nix anti-patterns
    ruff-format.enable = true; # python (packages/vault-sync)
    shfmt.enable = true;
    prettier.enable = true; # yaml (.github/workflows), markdown, json
  };

  # Linters rewrite code; nixfmt runs last so their output is formatted.
  settings.formatter.deadnix.priority = 1;
  settings.formatter.statix.priority = 2;
  settings.formatter.nixfmt.priority = 3;

  # Keep `case` bodies indented (shfmt's `-ci`); its default de-indents them.
  # List-typed, so this concatenates with the shfmt module's own flags.
  settings.formatter.shfmt.options = [ "-ci" ];

  settings.global.excludes = [
    # Generated / externally-managed lock files — never hand-format.
    "flake.lock"
    "packages/obsidian-headless/package-lock.json"
  ];
}
