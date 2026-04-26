local M = {}

local logger = hs.logger.new("WindowKit.autoclose", "info")

local lastFocused = {}
local timer = nil

function M.start(parent)
    local rules = (parent.autoclose and parent.autoclose.rules) or {}
    if #rules == 0 then
        logger.i("autoclose: no rules; skipping")
        return
    end

    local wf = hs.window.filter.new(true)
    wf:subscribe(hs.window.filter.windowFocused, function(win)
        if win then
            lastFocused[win:id()] = hs.timer.secondsSinceEpoch()
            logger.i("Focus tracked: " .. win:title() .. " [" .. win:id() .. "]")
        end
    end)

    local function ensureTracked(win)
        local id = win:id()
        if not lastFocused[id] then
            lastFocused[id] = hs.timer.secondsSinceEpoch()
            logger.i("New window tracked: " .. win:title() .. " [" .. id .. "]")
        end
    end

    timer = hs.timer.doEvery(60, function()
        local now = hs.timer.secondsSinceEpoch()
        local allWindows = hs.window.allWindows()

        for _, win in ipairs(allWindows) do ensureTracked(win) end

        local activeIds = {}
        for _, win in ipairs(allWindows) do activeIds[win:id()] = true end
        for id in pairs(lastFocused) do
            if not activeIds[id] then
                logger.i("Pruned closed window [" .. id .. "]")
                lastFocused[id] = nil
            end
        end

        for _, rule in ipairs(rules) do
            local matching = {}
            for _, win in ipairs(allWindows) do
                if win:title():find(rule.titlePattern, 1, true) then
                    table.insert(matching, win)
                end
            end

            local minCount = rule.count or 1
            if #matching >= minCount then
                table.sort(matching, function(a, b)
                    return (lastFocused[a:id()] or 0) > (lastFocused[b:id()] or 0)
                end)

                local keepCount = math.max(1, minCount - 1)
                for i = keepCount + 1, #matching do
                    local win = matching[i]
                    local age = now - (lastFocused[win:id()] or 0)
                    if age > rule.timeout then
                        local msg = "Closed stale duplicate: " .. win:title() .. " (idle " .. math.floor(age / 60) .. "min)"
                        logger.i(msg)
                        hs.notify.new({ title = "Auto-Close", informativeText = msg }):send()
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

    logger.i("Auto-close stale duplicates loaded with " .. #rules .. " rule(s)")
end

function M.stop()
    if timer then timer:stop(); timer = nil end
end

return M
