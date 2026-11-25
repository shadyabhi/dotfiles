return function(directory)

  local function codex_dir(process)
    if not process or not process.pid then return end
    local executable = process.invoked_path or process.path or process.script or ""
    if not executable:match("/codex$") and not executable:match("/codex/versions/") then return end
    local result = rex.exec{ "/usr/bin/ruby", directory .. "/codex-cwd.rb", tostring(math.floor(process.pid)) }
    if not result or not result.ok then return end
    local cwd = result.stdout and result.stdout:match("([^\r\n]+)")
    if cwd and cwd ~= "" then return cwd end
  end

  local function pane_dir(block_id)
    local terminal = "com.superlogical.terminal"
    local process = rex.block.call(terminal, "process", { block_id = block_id })
    local foreground = process and process.foreground
    local cwd = codex_dir(foreground) or (foreground and foreground.cwd)
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
