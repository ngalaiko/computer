{ inputs, pkgs, ... }:
let
  unstable = import inputs.nixpkgs-unstable { inherit (pkgs.stdenv.hostPlatform) system; };
in
{
  programs.jujutsu = {
    enable = true;
    package = unstable.jujutsu;
    settings = {
      user = {
        name = "Nikita Galaiko";
        email = "nikita@galaiko.rocks";
      };

      signing = {
        behavior = "drop";
        backend = "ssh";
        key = "~/.ssh/id_ed25519.pub";
      };

      git.sign-on-push = true;

      # https://andre.arko.net/2025/09/28/stupid-jj-tricks/
      aliases = {
        # tug: bring nearest bookmark up to recent commit
        tug = [
          "bookmark"
          "move"
          "--from"
          "heads(::@ & bookmarks())"
          "--to"
          "closest_pushable(@)"
        ];
        pr = [
          "util"
          "exec"
          "--"
          "bash"
          "-c"
          ''
            gh pr create --head $(jj log -r 'closest_bookmark(@)' -T 'bookmarks' --no-graph | cut -d ' ' -f 1) --web
          ''
        ];
        ll = [
          "log"
          "-T"
          "log_with_files"
        ];

        # start: start a new revision base on the latest trunk
        start = [
          "new"
          "-r"
          "trunk()"
        ];

        # tidy: abandon empty, undescribed, mutable, non-merge commits
        tidy = [
          "abandon"
          ''empty() & description(exact:"") & mutable() & ~@ & ~merges()''
        ];

        # retrunk: rebase the current branch onto the latest trunk
        retrunk = [
          "rebase"
          "-d"
          "trunk()"
        ];
      };

      templates = {
        git_push_bookmark = ''concat("ngalaiko/push-", change_id.short())'';
        draft_commit_description = ''
          concat(
            coalesce(description, default_commit_description, "\n"),
            surround(
              "\nJJ: This commit contains the following changes:\n", "",
              indent("JJ:     ", diff.stat(72)),
            ),
            "\nJJ: ignore-rest\n",
            diff.git(),
          )
        '';
        log_node = ''
          if(self && !current_working_copy && !immutable && !conflict && in_branch(self),
            "◇",
            builtin_log_node
          )
        '';
      };

      revset-aliases = {
        "closest_bookmark(to)" = "heads(::to & bookmarks())";
        "closest_pushable(to)" =
          ''heads(::to & mutable() & ~description(exact:"") & (~empty() | merges()))'';
      };

      template-aliases = {
        "format_timestamp(timestamp)" = "timestamp.ago()";
        "in_branch(commit)" = ''commit.contained_in("immutable_heads()..bookmarks()")'';
      };

      ui = {
        editor = "nvim";
        default-command = "status";
        diff-formatter = [
          "difft"
          "--display"
          "inline"
          "--color=always"
          "$left"
          "$right"
        ];
        diff-editor = ":builtin";
      };
    };
  };

  # ui.diff-formatter
  home.packages = [ pkgs.difftastic ];

  # work identity, scoped by repo path
  xdg.configFile."jj/conf.d/cerve.toml".text = ''
    --when.repositories = ["~/Developer/cerve"]

    [user]
    email = "nikita.galaiko@cerve.com"
  '';
}
