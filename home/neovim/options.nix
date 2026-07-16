{ ... }:
{
  programs.nixvim = {
    globals.mapleader = ",";

    clipboard.register = "unnamedplus";

    opts = {
      shiftwidth = 4;
      tabstop = 4;
      softtabstop = 4;

      mouse = "";

      relativenumber = true;
      number = true;

      infercase = true;
      ignorecase = true;

      swapfile = false;
      backup = false;
      undodir.__raw = ''os.getenv("HOME") .. "/.vim/undodir"'';
      undofile = true;

      termguicolors = true;

      scrolloff = 8;
      signcolumn = "yes";
      updatetime = 50;
    };

    # fresh machines: plugins expect the state dirs to exist (neo-tree logs
    # into stdpath data at setup); runs before plugin configs.
    extraConfigLuaPre = ''
      vim.fn.mkdir(vim.fn.stdpath("data"), "p")
      vim.fn.mkdir(os.getenv("HOME") .. "/.vim/undodir", "p")
    '';

    extraConfigLua = ''
      vim.opt.isfname:append("a-a")

      if vim.fn.getenv("TERM_PROGRAM") == "ghostty" then
        vim.opt.title = true
        vim.opt.titlestring = "%{fnamemodify(getcwd(), ':t')}"
      end

      vim.diagnostic.config({
        virtual_text = false,
        virtual_lines = true,
      })
    '';
  };
}
