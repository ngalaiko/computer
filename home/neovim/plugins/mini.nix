{ pkgs, ... }:
let
  # rg skips hidden files, which the git tool it replaces in <C-g> did not.
  ripgreprc = pkgs.writeText "ripgreprc" ''
    --hidden
    --glob=!.git/
    --glob=!.jj/
  '';

  # mini.diff's git source reads the git index, which a jj workspace has no
  # trace of. Reference text is the file at @-, i.e. the working-copy parent.
  # No apply_hunks: jj has no index to stage into.
  jjDiffSource = ''
    (function()
      local set_ref = function(buf_id, path, root)
        vim.system(
          { "jj", "file", "show", "-r", "@-", path },
          { cwd = root, text = true },
          vim.schedule_wrap(function(out)
            if not vim.api.nvim_buf_is_valid(buf_id) then return end
            local diff = require("mini.diff")
            -- non-zero means the path is absent from @-, same as untracked
            if out.code ~= 0 then return diff.fail_attach(buf_id) end
            pcall(diff.set_ref_text, buf_id, out.stdout)
          end)
        )
      end

      local watchers = {}

      local attach = function(buf_id)
        local path = vim.api.nvim_buf_get_name(buf_id)
        if path == "" or vim.fn.filereadable(path) ~= 1 then return false end
        local root = vim.fs.root(path, ".jj")
        if root == nil then return false end

        set_ref(buf_id, path, root)

        -- 'checkout' is rewritten whenever the workspace's working-copy commit
        -- moves, which is when @- can change. Watch the directory: the write is
        -- a rename, which drops a watch on the file itself.
        local fs_event, timer = vim.uv.new_fs_event(), vim.uv.new_timer()
        fs_event:start(vim.fs.joinpath(root, ".jj", "working_copy"), {}, function(_, filename, _)
          if filename ~= "checkout" then return end
          timer:stop()
          timer:start(50, 0, function() set_ref(buf_id, path, root) end)
        end)
        watchers[buf_id] = { fs_event = fs_event, timer = timer }
      end

      local detach = function(buf_id)
        local w = watchers[buf_id]
        watchers[buf_id] = nil
        if w == nil then return end
        w.fs_event:stop()
        w.timer:stop()
      end

      return { name = "jj", attach = attach, detach = detach }
    end)()
  '';
in
{
  # mini.pick and the jj diff source shell out to these; nvim must find them
  # regardless of PATH.
  programs.nixvim.extraPackages = with pkgs; [
    jujutsu
    ripgrep
  ];

  # scoped to nvim; leaves rg in the shell alone
  programs.nixvim.extraConfigLua = ''
    vim.env.RIPGREP_CONFIG_PATH = "${ripgreprc}"
  '';

  programs.nixvim.plugins.mini = {
    enable = true;
    modules = {
      diff = {
        # jj first: it also wins in a colocated repo, where @- is the better
        # reference than the git index jj rewrites behind you.
        source.__raw = ''{ ${jjDiffSource}, require("mini.diff").gen_source.git() }'';
        view = {
          style = "sign";
          signs = {
            add = "▎";
            change = "▎";
            delete = "";
          };
        };
      };
      pick = { };
    };
  };
}
