local logger = hs.logger.new('autoclose', 'info')

-- Configuration: add rules for windows to auto-close when duplicates exist
local rules = {
    { titlePattern = "Google Meet", timeout = 300, count = 2 }, -- close when >2 exist, after 5min idle
}

-- Track last-focused time per window ID
local lastFocused = {}

-- Record focus time for any window that gains focus
local wf = hs.window.filter.new(true)
wf:subscribe(hs.window.filter.windowFocused, function(win)
    if win then
        lastFocused[win:id()] = hs.timer.secondsSinceEpoch()
        logger.i("Focus tracked: " .. win:title() .. " [" .. win:id() .. "]")
    end
end)

-- Stamp newly seen windows with current time
local function ensureTracked(win)
    local id = win:id()
    if not lastFocused[id] then
        lastFocused[id] = hs.timer.secondsSinceEpoch()
        logger.i("New window tracked: " .. win:title() .. " [" .. id .. "]")
    end
end

-- Periodic sweep
hs.timer.doEvery(60, function()
    local now = hs.timer.secondsSinceEpoch()
    local allWindows = hs.window.allWindows()

    -- Ensure all windows are tracked
    for _, win in ipairs(allWindows) do
        ensureTracked(win)
    end

    -- Clean up entries for closed windows
    local activeIds = {}
    for _, win in ipairs(allWindows) do
        activeIds[win:id()] = true
    end
    for id in pairs(lastFocused) do
        if not activeIds[id] then
            logger.i("Pruned closed window [" .. id .. "]")
            lastFocused[id] = nil
        end
    end

    -- Check each rule
    for _, rule in ipairs(rules) do
        -- Find matching windows
        local matching = {}
        for _, win in ipairs(allWindows) do
            if win:title():find(rule.titlePattern, 1, true) then
                table.insert(matching, win)
            end
        end

        local minCount = rule.count or 1
        if #matching >= minCount then
            -- Sort by last focused time descending (most recent first)
            table.sort(matching, function(a, b)
                return (lastFocused[a:id()] or 0) > (lastFocused[b:id()] or 0)
            end)

            -- Always keep at least (minCount - 1) windows, plus never close the most recent
            local keepCount = math.max(1, minCount - 1)
            for i = keepCount + 1, #matching do
                local win = matching[i]
                local age = now - (lastFocused[win:id()] or 0)
                if age > rule.timeout then
                    local msg = "Closed stale duplicate: " .. win:title() .. " (idle " .. math.floor(age / 60) .. "min)"
                    logger.i(msg)
                    hs.notify.new({title = "Auto-Close", informativeText = msg}):send()
                    win:close()
                    lastFocused[win:id()] = nil
                else
                    local remaining = math.ceil((rule.timeout - age) / 60)
                    logger.i("Will close \"" .. win:title() .. "\" [" .. win:id() .. "] in ~" .. remaining .. "min (idle " .. math.floor(age / 60) .. "min)")
                end
            end
        end
    end
end)

logger.i("Auto-close stale duplicates loaded")
