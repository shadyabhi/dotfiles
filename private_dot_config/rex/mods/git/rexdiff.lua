-- Open git changes beside the focused pane, using its current directory.
local function rexdiff_pane_dir(block_id)
  local terminal = "com.superlogical.terminal"
  local result = rex.block.call(terminal, "pwd", { block_id = block_id })
  if result and result.pwd and result.pwd ~= "" then return result.pwd end
  local process = rex.block.call(terminal, "process", { block_id = block_id })
  return process and process.foreground and process.foreground.cwd or ""
end

rex.action{
  name = "rexdiff_show",
  title = "rexdiff: Open Changes",
  description = "Opens git changes beside the focused pane for its current directory.",
  category = "Git",
  keywords = "git diff changes rexdiff",
  run = function(ctx)
    if not ctx.block_id then return end
    local result, err = rex.exec(
      { os.getenv("HOME") .. "/.local/bin/rexdiff", "show", "--cwd", rexdiff_pane_dir(ctx.block_id) },
      { env = { REX_SESSION = ctx.session_id, REX_BLOCK = ctx.block_id }, timeout = 15 }
    )
    if not result then
      rex.log("error", "rexdiff: " .. tostring(err))
    elseif not result.ok then
      rex.log("warn", "rexdiff: " .. result.stderr)
    end
  end,
}

rex.bind("ctrl+cmd+d", "rexdiff_show")
