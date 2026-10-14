-- splits
rex.bind("ctrl+alt+s", "pane.split", { direction = "down" })
rex.bind("ctrl+alt+v", "pane.split", { direction = "right" })
rex.bind("ctrl+alt+h", "pane.focus", { direction = "left" })
rex.bind("ctrl+alt+j", "pane.focus", { direction = "down" })
rex.bind("ctrl+alt+k", "pane.focus", { direction = "up" })
rex.bind("ctrl+alt+l", "pane.focus", { direction = "right" })

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
