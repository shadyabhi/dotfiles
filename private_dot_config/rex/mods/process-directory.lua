return function(directory)
  local function agent_name(process)
    for _, executable in ipairs{ process.invoked_path or "", process.path or "", process.script or "" } do
      if executable:match("/codex$") or executable:match("/codex/versions/") or executable:match("/@openai/codex/") then
        return "codex"
      end
      if executable:match("/claude$") or executable:match("/claude/versions/") or executable:match("/@anthropic%-ai/claude%-code/") then
        return "claude"
      end
    end
  end

  return function(process)
    if not process then return end
    local agent = agent_name(process)
    if agent and process.pid then
      local result = rex.exec{ "/usr/bin/ruby", directory .. "/agent-cwd.rb", tostring(math.floor(process.pid)), agent }
      local cwd = result and result.ok and result.stdout and result.stdout:match("([^\r\n]+)")
      if cwd and cwd ~= "" then return cwd end
    end
    return process.cwd
  end
end
