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
        # Public key assumed present on disk at this path on every host. The
        # private half lives wherever the host keeps it: hand-generated in
        # ~/.ssh on exedev, sealed in the Secure Enclave and reached via
        # Secretive's ssh-agent on the mac (see hosts/macbook/home/{ssh,jj}.nix).
        key = "~/.ssh/id_ed25519.pub";
      };

      git.sign-on-push = true;

      # never push wip commits (jj refuses, and refuses their descendants)
      git.private-commits = "wip()";

      # https://andre.arko.net/2025/09/28/stupid-jj-tricks/
      aliases = {
        # float: if @- is a working-copy merge with wip parents, un-merge it —
        # the real commit becomes a clean child of trunk, each wip is
        # re-parented onto it as a sibling, and @ is re-merged so the wip
        # changes stay in the working tree. No-op when @- has no wip parents.
        float = [
          "util"
          "exec"
          "--"
          "bash"
          "-c"
          ''
            set -euo pipefail
            # R = @-, but only when @ has a single parent (i.e. @ is not already
            # a floated merge). Otherwise there is nothing to float.
            R=$(jj log --no-graph -r '@-' -T 'change_id.short() ++ "\n"')
            if [ "$(printf '%s' "$R" | grep -c .)" = "1" ]; then
              wips=$(jj log --no-graph -r "parents($R) & wip()" -T 'change_id.short() ++ " "')
              if [ -n "''${wips// /}" ]; then
                base=$(jj log --no-graph -r "parents($R) ~ wip()" -T 'change_id.short()')
                jj rebase -s "$R" -d "$base" >/dev/null            # R (+@) onto trunk, drop wip parents
                for w in $wips; do jj rebase -r "$w" -d "$R" >/dev/null; done  # lift each wip onto R
                dflags=""; for w in $wips; do dflags="$dflags -d $w"; done
                jj rebase -r @ -d "$R" $dflags >/dev/null          # @ = merge(R, wips...)
              fi
            fi
          ''
        ];

        # tug: float wip commits off the latest real commit (see `float`), then
        # move the nearest bookmark up to closest_pushable (which excludes wip).
        # Usual flow: work in a wip-merged @, `jj commit`, `jj tug`.
        tug = [
          "util"
          "exec"
          "--"
          "bash"
          "-c"
          ''
            set -euo pipefail
            jj float
            jj bookmark move --from 'heads(::@ & bookmarks())' --to 'closest_pushable(@)'
          ''
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
        # commits whose description starts with "wip"
        "wip()" = ''description(glob:"wip*")'';
        "closest_bookmark(to)" = "heads(::to & bookmarks())";
        # closest pushable ancestor: mutable, described, non-empty (or merge),
        # and not wip, so tug stops below wip commits
        "closest_pushable(to)" =
          ''heads(::to & mutable() & ~description(exact:"") & ~wip() & (~empty() | merges()))'';
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
}
