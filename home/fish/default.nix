{ pkgs, ... }:
{
  # __nvim_fzf_open
  home.packages = [ pkgs.fzf ];

  programs.fish = {
    enable = true;

    shellAbbrs.vim = "nvim";

    interactiveShellInit = ''
      set --global fish_greeting
      set --global fish_key_bindings fish_default_key_bindings

      bind \cp '__nvim_fzf_open'

      # Mono Smoke
      set --global fish_color_autosuggestion 777777
      set --global fish_color_cancel --reverse
      set --global fish_color_command ffffff
      set --global fish_color_comment bcbcbc
      set --global fish_color_cwd green
      set --global fish_color_cwd_root red
      set --global fish_color_end 949494
      set --global fish_color_error 585858
      set --global fish_color_escape 00a6b2
      set --global fish_color_history_current --bold
      set --global fish_color_host normal
      set --global fish_color_host_remote
      set --global fish_color_keyword
      set --global fish_color_match --background=brblue
      set --global fish_color_normal normal
      set --global fish_color_operator 00a6b2
      set --global fish_color_option
      set --global fish_color_param d7d7d7
      set --global fish_color_quote a8a8a8
      set --global fish_color_redirection 808080
      set --global fish_color_search_match bryellow --background=brblack
      set --global fish_color_selection white --bold --background=brblack
      set --global fish_color_status red
      set --global fish_color_user brgreen
      set --global fish_color_valid_path --underline
      set --global fish_pager_color_background
      set --global fish_pager_color_completion normal
      set --global fish_pager_color_description B3A06D
      set --global fish_pager_color_prefix normal --bold --underline
      set --global fish_pager_color_progress brwhite --background=cyan
      set --global fish_pager_color_secondary_background
      set --global fish_pager_color_secondary_completion
      set --global fish_pager_color_secondary_description
      set --global fish_pager_color_secondary_prefix
      set --global fish_pager_color_selected_background --background=brblack
      set --global fish_pager_color_selected_completion
      set --global fish_pager_color_selected_description
      set --global fish_pager_color_selected_prefix
    '';

    functions = {
      __nvim_fzf_open = ''
        # Check if we're in a git repo
        if git rev-parse --git-dir >/dev/null 2>&1
            # In git repo: show tracked files + directories
            set selection (begin
                git ls-files
                git ls-tree -d -r --name-only HEAD
            end | sort -u | fzf)
        else
            # Not in git repo: show all files and directories (including hidden)
            set selection (find . -type f -o -type d | sed 's|^\./||' | grep -v '^\.$' | fzf)
        end

        if test -n "$selection"
            if test -d "$selection"
                cd "$selection" && commandline -f repaint
            else
                nvim "$selection"
            end
        end
      '';

      fish_prompt = {
        description = "Write out the prompt";
        body = ''
          set -l last_status $status
          set -l normal (set_color normal)
          set -l status_color (set_color normal)
          set -l cwd_color (set_color normal)
          set -l vcs_color (set_color normal)
          set -l prompt_status ""

          # Since we display the prompt on a new line allow the directory names to be longer.
          set -q fish_prompt_pwd_dir_length
          or set -lx fish_prompt_pwd_dir_length 0

          # Color the prompt differently when we're root
          set -l suffix '❯'
          if functions -q fish_is_root_user; and fish_is_root_user
              if set -q fish_color_cwd_root
                  set cwd_color (set_color $fish_color_cwd_root)
              end
              set suffix '#'
          end

          # Color the prompt in red on error
          if test $last_status -ne 0
              set status_color (set_color $fish_color_error)
              set prompt_status $status_color "[" $last_status "]" $normal
          end

          # host label (set per machine via nix)
          if set -q prompt_host
              echo -n -s (set_color brblack) $prompt_host $normal ' '
          end

          echo -s $cwd_color (prompt_pwd) $vcs_color (fish_vcs_prompt) $normal ' ' $prompt_status
          echo -n -s $status_color $suffix ' ' $normal
        '';
      };

      fish_title = ''
        set -q fish_prompt_pwd_dir_length
        or set -lx fish_prompt_pwd_dir_length 0

        echo (prompt_pwd)
      '';

      fish_vcs_prompt = {
        description = "Print all vcs prompts";
        body = ''
          # If a prompt succeeded, we assume that it's printed the correct info.
          # This is so we don't try git if jj already worked.
          fish_jj_prompt $argv
          or fish_git_prompt $argv
        '';
      };

      fish_jj_prompt = {
        description = "Write out the jj prompt";
        body = ''
          # Is jj installed?
          if not command -sq jj
              return 1
          end

          # Are we in a jj repo?
          if not jj root --quiet &>/dev/null
              return 1
          end

          # Dirty/clean status of @
          set -l wc_status (jj log --ignore-working-copy --no-graph -r @ -T 'if(empty, "clean", "dirty")' 2>/dev/null)

          # If @ has bookmarks, show them directly
          set -l bookmark_display (jj log --ignore-working-copy --no-graph --color always -r @ -T 'local_bookmarks.join(", ")' 2>/dev/null)
          if test -n "$bookmark_display"
              printf ' [%s %s]' "$bookmark_display" "$wc_status"
              return 0
          end

          # Otherwise, show the closest ancestor bookmark prefixed with ~
          # and append +N for the number of commits between it and @ (excluding @)
          set -l closest (jj log --ignore-working-copy --no-graph --color always -r 'heads(::@ & bookmarks())' -T '"~" ++ local_bookmarks.join(", ~")' 2>/dev/null)
          if test -z "$closest"
              return 0
          end

          set -l ahead (string length -- (jj log --ignore-working-copy --no-graph -r 'heads(::@ & bookmarks())::@- ~ heads(::@ & bookmarks())' -T '"x"' 2>/dev/null))
          if test -n "$ahead" -a "$ahead" -gt 0
              printf ' [%s +%s %s]' "$closest" "$ahead" "$wc_status"
          else
              printf ' [%s %s]' "$closest" "$wc_status"
          end
        '';
      };

      reload = "fish -l";
    };
  };
}
