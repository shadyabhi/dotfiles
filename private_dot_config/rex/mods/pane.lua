return function(process_directory)
  rex.bind("ctrl+a>h", "pane.focus", { direction = "left", wrap = false })
  rex.bind("ctrl+a>j", "pane.focus", { direction = "down", wrap = false })
  rex.bind("ctrl+a>k", "pane.focus", { direction = "up", wrap = false })
  rex.bind("ctrl+a>l", "pane.focus", { direction = "right", wrap = false })

  local function split_in_process_directory(ctx, direction)
    if not ctx.block_id then return false end
    local process, process_error = rex.block.call("com.superlogical.terminal", "process", {
      block_id = ctx.block_id,
    })
    local cwd = process_directory(process and process.foreground)
    if not cwd or cwd == "" then
      error("Split pane: could not read the foreground process directory: " .. tostring(process_error or "directory unavailable"), 0)
    end
    local result, err = rex.call("session.new_split", {
      session_id = ctx.session_id,
      anchor_id = ctx.block_id,
      direction = direction,
      side = "after",
      focus = true,
      layout = { block = {
        flavor = "com.superlogical.terminal.shell",
        options = { cwd = cwd },
      } },
    })
    if not result then error("Split pane: " .. tostring(err), 0) end
    return true
  end

  rex.bind("ctrl+a>s", function(ctx)
    return split_in_process_directory(ctx, "vertical")
  end)
  rex.bind("ctrl+a>v", function(ctx)
    return split_in_process_directory(ctx, "horizontal")
  end)
  rex.bind("ctrl+a>b", "pane.move_to_new_tab")
end
