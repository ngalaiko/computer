-- splits
rex.bind("ctrl+alt+s", "pane.split", { direction = "down" })
rex.bind("ctrl+alt+v", "pane.split", { direction = "right" })
rex.bind("ctrl+alt+h", "pane.focus", { direction = "left" })
rex.bind("ctrl+alt+j", "pane.focus", { direction = "down" })
rex.bind("ctrl+alt+k", "pane.focus", { direction = "up" })
rex.bind("ctrl+alt+l", "pane.focus", { direction = "right" })

-- Vim handles its splits and hands off at the edge.
local function is_vim(process)
  if not process then
    return false
  end
  local name = (process.name or ""):gsub("^%.", ""):gsub("%-wrapped$", "")
  return name == "nvim" or name == "vim"
end

for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  rex.bind("ctrl+" .. key, function(ctx)
    local process = rex.block.call("com.superlogical.terminal", "process", {
      session_id = ctx.session_id,
      block_id = ctx.block_id,
    })
    if not process or is_vim(process.foreground) then
      return false
    end
    for _, ancestor in ipairs(process.ancestors or {}) do
      if is_vim(ancestor) then
        return false
      end
    end
    local result = rex.session.focus_direction({
      session_id = ctx.session_id,
      direction = direction,
      wrap = true,
    })
    return result ~= nil
  end)
end

-- tabs
rex.bind("cmd+t", "client.tab.new")
rex.bind("cmd+w", "pane.close")
rex.bind("ctrl+shift+l", "client.tab.next")
rex.bind("ctrl+shift+h", "client.tab.previous")
for i = 1, 9 do
  rex.bind("cmd+[Digit" .. i .. "]", "client.tab.goto", { index = i })
end

-- font
rex.bind("cmd+=", "client.font.increase")
rex.bind("cmd+shift+=", "client.font.increase")
rex.bind("cmd+-", "client.font.decrease")
rex.bind("cmd+0", "client.font.reset")
