local M = {}

local logger = hs.logger.new("WindowKit.grid", "info")

local function getWinInfo()
    local win = hs.window.focusedWindow()
    if win == nil then return nil, nil, nil, nil end
    local screen = win:screen()
    return win, screen, hs.grid.getGrid(screen), hs.grid.get(win)
end

local function drawGrid(grid, windows)
    local n = 1
    for h = 0, grid.h - 1 do
        for w = 0, hs.grid.getGrid().w - 1 do
            logger:i(w, h, n, windows[n])
            hs.grid.set(windows[n], { x = w, y = h, w = 0, h = 0 }, windows[n]:screen())
            n = n + 1
            if n > hs.grid.getGrid().w * hs.grid.getGrid().h then return end
        end
    end
end

function M.bind(parent)
    hs.grid.setGrid(parent.gridDims or "3x2")
    hs.grid.setMargins(parent.gridMargins or "1x1")

    local hk = parent.hyperkey
    local spaces = parent._spaces

    hk:bind("h", "right", function()
        local win = hs.window.focusedWindow()
        if not win then return end
        if #hs.screen.allScreens() == 1 then
            local g = hs.grid.get(win)
            local sg = hs.grid.getGrid(win:screen())
            if g.x + g.w >= sg.w then
                if spaces then spaces.moveWindowOneSpace("right", parent) end
                return
            end
        end
        hs.grid.pushWindowRight()
    end)
    hk:bind("h", "left", function()
        local win = hs.window.focusedWindow()
        if not win then return end
        if #hs.screen.allScreens() == 1 then
            local g = hs.grid.get(win)
            if g.x <= 0 then
                if spaces then spaces.moveWindowOneSpace("left", parent) end
                return
            end
        end
        hs.grid.pushWindowLeft()
    end)
    hk:bind("h", "down", hs.grid.pushWindowDown)
    hk:bind("h", "up", hs.grid.pushWindowUp)

    hk:bind("hca", "up", function()
        local win, _, sg, g = getWinInfo()
        if win == nil then return end
        if g.y + g.h >= sg.h and g.y ~= 0 then
            g.y = g.y - 1; g.h = g.h + 1; hs.grid.set(win, g)
        else
            g.h = g.h - 1; hs.grid.set(win, g)
        end
    end)
    hk:bind("hca", "down", function()
        local win, _, sg, g = getWinInfo()
        if win == nil then return end
        if g.y + g.h == sg.h then
            g.y = g.y + 1; g.h = g.h - 1; hs.grid.set(win, g)
        else
            g.h = g.h + 1; hs.grid.set(win, g)
        end
    end)
    hk:bind("hca", "right", function()
        local win, _, sg, g = getWinInfo()
        if win == nil then return end
        if g.x + g.w == sg.w then
            g.x = g.x + 1; g.w = g.w - 1; hs.grid.set(win, g)
        else
            g.w = g.w + 1; hs.grid.set(win, g)
        end
    end)
    hk:bind("hca", "left", function()
        local win, _, _, g = getWinInfo()
        if win == nil then return end
        if g.x ~= 0 then
            g.x = g.x - 1; g.w = g.w + 1; hs.grid.set(win, g)
        else
            g.w = g.w - 1; hs.grid.set(win, g)
        end
    end)

    hk:bind("hca", "s", function()
        local win = hs.window.focusedWindow()
        if win == nil then return end
        hs.grid.snap(win)
    end)

    hk:bind("hca", "h", function() hs.window.focusedWindow().focusWindowWest() end)
    hk:bind("hca", "l", function() hs.window.focusedWindow().focusWindowEast() end)
    hk:bind("hca", "k", function() hs.window.focusedWindow().focusWindowNorth() end)
    hk:bind("hca", "j", function() hs.window.focusedWindow().focusWindowSouth() end)

    local chooser = hs.chooser.new(function(choice)
        if not choice then return end
        hs.grid.setGrid(choice["text"])
        drawGrid(hs.grid.getGrid(), hs.window.filter.defaultCurrentSpace:getWindows())
    end)
    local choices = {}
    for _, dims in ipairs(parent.gridChoices or { "2x1", "3x1", "3x2" }) do
        table.insert(choices, { text = dims .. "\n" })
    end
    chooser:choices(choices)
    hk:bind("hca", "g", function() chooser:show() end)

    hk:bind("h", "a", function()
        drawGrid(hs.grid.getGrid(), hs.window.filter.defaultCurrentSpace:getWindows())
    end)

    hk:bind("hs", "g", function()
        local windows = hs.window.filter.defaultCurrentSpace:getWindows()
        local nGrid = math.ceil(math.sqrt(#windows))
        if parent.notifyFn then
            parent.notifyFn("Grid", "Found " .. #windows .. " windows, switching to " .. nGrid .. "x" .. nGrid .. " grid", 1.5)
        end
        hs.grid.setGrid(nGrid .. "x" .. nGrid)
        drawGrid(hs.grid.getGrid(), hs.window.filter.defaultCurrentSpace:getWindows())
    end)
end

return M
