{ ... }:
let
  key = mode: k: action: {
    inherit mode action;
    key = k;
    options.silent = true;
  };
  raw = mode: k: action: {
    inherit mode;
    key = k;
    action.__raw = action;
    options.silent = true;
  };
in
{
  programs.nixvim.keymaps = [
    # trouble
    (key "n" "<space>q" "<cmd>Trouble diagnostics toggle<CR>")

    # mini.pick
    (raw "n" "<C-p>" ''function() require("mini.pick").builtin.files({ tool = "git" }) end'')
    (raw "n" "<C-g>" ''function() require("mini.pick").builtin.grep_live({ tool = "git" }) end'')

    # aerial
    (key "n" "<leader>tt" "<cmd>AerialToggle<CR>")

    # lsp
    (key "n" "gd" "<cmd>lua vim.lsp.buf.definition()<CR>")

    # conform
    (raw "n" "<space>f" ''function() require("conform").format() end'')

    # neotree
    (key "n" "<leader>o" ":Neotree toggle<CR>")
    (key "n" "<leader>O" ":Neotree reveal<CR>")

    # split tab vertically and horizontally
    (raw "n" "<leader>v" "vim.cmd.vsp")
    (raw "n" "<leader>s" "vim.cmd.sp")

    # move between nvim splits; ghostty passes <C-hjkl> through (via
    # performable:goto_split) when there's no ghostty split in that direction
    (key "n" "<C-h>" "<C-w>h")
    (key "n" "<C-j>" "<C-w>j")
    (key "n" "<C-k>" "<C-w>k")
    (key "n" "<C-l>" "<C-w>l")

    # Move lines around (macOS <A-j> = ˚ <A-k> = ∆)
    (key "n" "∆" ":m+<CR>==")
    (key "n" "˚" ":m-2<CR>==")
    (key "i" "∆" "<Esc>:m .+1<CR>==gi")
    (key "i" "˚" "<Esc>:m .-2<CR>==gi")
    (key "v" "∆" ":m'>+<CR>gv=gv")
    (key "v" "˚" ":m'<-2<CR>gv=gv")

    # Double ESC to unhilight search
    (key "n" "<Esc><Esc>" "<Esc>:nohlsearch<CR><Esc>")

    # Treat long lines as break lines (useful when moving around in them)
    (key "" "j" "gj")
    (key "" "k" "gk")

    # visual shifting (does not exit Visual mode)
    (key "v" "<" "<gv")
    (key "v" ">" ">gv")

    # visual shifting up and down
    (key "v" "J" ": m'>+1<CR>gv=gv")
    (key "v" "K" ": m'<-2<CR>gv=gv")
  ];
}
