rex.bind("ctrl+a>h", "pane.focus", { direction = "left", wrap = false })
rex.bind("ctrl+a>j", "pane.focus", { direction = "down", wrap = false })
rex.bind("ctrl+a>k", "pane.focus", { direction = "up", wrap = false })
rex.bind("ctrl+a>l", "pane.focus", { direction = "right", wrap = false })

rex.bind("ctrl+a>s", "pane.split", { direction = "down" })
rex.bind("ctrl+a>v", "pane.split", { direction = "right" })
