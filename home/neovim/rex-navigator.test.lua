-- Run: nvim --headless -u NONE -l home/neovim/rex-navigator.test.lua
local calls = {}
vim.env.REX_SESSION = "session:test"
vim.fn.executable = function(command)
  assert(command == "rex")
  return 1
end
vim.system = function(command, options, callback)
  calls[#calls + 1] = command
  assert(options.timeout == 1000)
  callback({ code = 0 })
end

dofile("home/neovim/rex-navigator.lua")
local function press(key)
  local mapping = vim.fn.maparg("<C-" .. key .. ">", "n", false, true)
  assert(type(mapping.callback) == "function")
  mapping.callback()
end

for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  calls = {}
  press(key)
  assert(#calls == 1)
  assert(vim.deep_equal(calls[1], {
    "rex", "--autostart=false", "focus", "-s", "session:test", "--wrap", direction,
  }))
end

for _, split in ipairs({ { "vsplit", "h", "l" }, { "split", "j", "k" } }) do
  vim.cmd("only")
  vim.cmd(split[1])
  vim.cmd("wincmd " .. split[2])
  local start = vim.api.nvim_get_current_win()
  calls = {}
  press(split[3])
  assert(vim.api.nvim_get_current_win() ~= start)
  assert(#calls == 0)
  press(split[2])
  assert(vim.api.nvim_get_current_win() == start)
  assert(#calls == 0)
end

vim.cmd("only")
calls = {}
vim.env.REX_SESSION = nil
press("h")
assert(#calls == 0)
vim.env.REX_SESSION = "session:test"
vim.fn.executable = function() return 0 end
press("l")
assert(#calls == 0)
print("Neovim navigation tests passed")
