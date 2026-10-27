-- Run: nvim --headless -u NONE -l hosts/macbook/home/rex/navigation.test.lua
local bindings, queued = {}, {}
local context_session = "session:test"
local process
rex = {
  bind = function(key, action) bindings[key] = action end,
  block = {
    call = function(creator, method, args)
      assert(creator == "com.superlogical.terminal" and method == "process")
      assert(args.session_id == "session:test" and args.block_id == "block:test")
      return process
    end,
  },
  client = {
    queue = function() error("a key handler cannot queue client actions") end,
  },
  session = {
    focus_direction = function(args)
      assert(args.session_id == context_session)
      assert(args.wrap == true)
      queued[#queued + 1] = args.direction
      return { revision = 1 }
    end,
  },
}
dofile("hosts/macbook/home/rex/init.lua")
local context = { session_id = "session:test", block_id = "block:test" }
for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  local navigate = bindings["ctrl+" .. key]
  assert(type(navigate) == "function")
  for _, name in ipairs({ "fish", "node", "bash" }) do
    process = { foreground = { name = name }, ancestors = {} }
    queued = {}
    assert(navigate(context) == true)
    assert(#queued == 1 and queued[1] == direction)
  end
  for _, name in ipairs({ "nvim", "vim", ".nvim-wrapped", "nvim-wrapped" }) do
    process = { foreground = { name = name } }
    queued = {}
    assert(navigate(context) == false and #queued == 0)
    process = { foreground = { name = "fish" }, ancestors = { { name = name } } }
    assert(navigate(context) == false and #queued == 0)
  end
  process = nil
  queued = {}
  assert(navigate(context) == false and #queued == 0)
  assert(bindings["ctrl+alt+" .. key] == "pane.focus")
end
print("Rex navigation tests passed")
