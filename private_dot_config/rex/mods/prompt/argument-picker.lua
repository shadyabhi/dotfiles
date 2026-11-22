-- Ask the active shell for its previous command, preserving its editing buffer.
rex.bind("cmd+.", function(ctx)
  if not ctx.block_id then return false end
  local result, err = rex.block.call("com.superlogical.terminal", "write", {
    block_id = ctx.block_id,
    data = "\24.", -- Ctrl+X, then period: the rex-last-argument ZLE widget.
  })
  if err then rex.log("warn", "last argument: " .. tostring(err)) end
  return true
end)

rex.action{
  name = "pick_last_argument",
  title = "Insert Previous Argument",
  description = "Choose an argument from the previous shell command, starting at the right.",
  category = "Shell",
  args = { words = "array" },
  run = function(ctx, args)
    local items = {}
    for i = #args.words, math.max(1, #args.words - 1999), -1 do
      items[#items + 1] = { id = tostring(i), title = args.words[i] }
    end
    if #items == 0 then return end
    local choice, why = rex.ui.pick{
      title = "Insert previous argument",
      placeholder = "Filter arguments…",
      items = items,
    }
    if choice then return { word = args.words[tonumber(choice)] } end
    if why ~= "cancelled" then
      error("Argument picker: " .. tostring(why), 0)
    end
  end,
}
