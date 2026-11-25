return function(directory, process_directory)

  local function pane_dir(block_id)
    local terminal = "com.superlogical.terminal"
    local process = rex.block.call(terminal, "process", { block_id = block_id })
    local foreground = process and process.foreground
    local cwd = process_directory(foreground)
    if cwd and cwd ~= "" then return cwd end
    local result = rex.block.call(terminal, "pwd", { block_id = block_id })
    return result and result.pwd
  end

  rex.action{
    name = "rexdiff_show",
    title = "revdiff: Open Changes",
    description = "Opens changes in the focused pane's Codex worktree or process directory and copies completed annotations to the clipboard.",
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
          options = { cwd = cwd, command = { "/bin/sh", directory .. "/revdiff-clipboard.sh", "--untracked" } },
        } },
      })
      if not result then error("revdiff: " .. tostring(err), 0) end
      return result
    end,
  }

  rex.bind("ctrl+cmd+d", "rexdiff_show")
end
