local directions = { h = "left", j = "down", k = "up", l = "right" }

for key, direction in pairs(directions) do
  vim.keymap.set("n", "<C-" .. key .. ">", function()
    local window = vim.api.nvim_get_current_win()
    vim.cmd("wincmd " .. key)
    if vim.api.nvim_get_current_win() ~= window or not vim.env.REX_SESSION then
      return
    end
    if vim.fn.executable("rex") ~= 1 then
      return
    end
    vim.system({ "rex", "--autostart=false", "focus", "-s", vim.env.REX_SESSION, "--wrap", direction }, {
      timeout = 1000,
    }, function(result)
      if result.code ~= 0 then
        vim.schedule(function()
          vim.notify("Rex navigation: " .. result.stderr, vim.log.levels.WARN)
        end)
      end
    end)
  end, { silent = true, desc = "Navigate Vim/Rex " .. direction })
end
