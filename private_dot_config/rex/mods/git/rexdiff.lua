local function pane_dir(block_id)
  local terminal = "com.superlogical.terminal"
  local process = rex.block.call(terminal, "process", { block_id = block_id })
  local cwd = process and process.foreground and process.foreground.cwd
  if cwd and cwd ~= "" then return cwd end
  local result = rex.block.call(terminal, "pwd", { block_id = block_id })
  return result and result.pwd
end

rex.action{
  name = "rexdiff_show",
  title = "revdiff: Open Changes",
  description = "Opens changes, including untracked files, beside the focused pane in its running process's directory.",
  category = "Git",
  keywords = "git diff changes revdiff rexdiff untracked",
  run = function(ctx)
    if not ctx.block_id then return end
    local cwd = pane_dir(ctx.block_id)
    if not cwd or cwd == "" then
      error("revdiff: could not determine the pane's working directory", 0)
    end
    local result, err = rex.call("session.new_split", {
      session_id = ctx.session_id,
      anchor_id = ctx.block_id,
      direction = "horizontal",
      side = "after",
      ratio = 0.55,
      focus = false,
      layout = { block = {
        flavor = "com.superlogical.terminal.shell",
        label = "revdiff",
        options = { cwd = cwd, command = { "/opt/homebrew/bin/revdiff", "--untracked" } },
      } },
    })
    if not result then error("revdiff: " .. tostring(err), 0) end
    return result
  end,
}

rex.bind("ctrl+cmd+d", "rexdiff_show")
