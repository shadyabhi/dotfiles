local M = {}

local INTERVAL = 2
local HOME = os.getenv("HOME")
local UID = hs.execute("id -u 2>/dev/null"):gsub("%s+", "")

local STATUS_ICON = { Input = "🔔", Working = "🤔", Idle = "💤" }

local BANNER_W      = 200
local BANNER_PAD    = 12
local BANNER_LINE_H = 18
local BANNER_MARGIN = 8

local MENUBAR_PY = HOME .. "/scripts/claude/menubar.py"

local function fetch_summary()
    local out = hs.execute(MENUBAR_PY .. " 2>/dev/null") or ""
    local ok, data = pcall(hs.json.decode, out)
    if not ok or type(data) ~= "table" then
        return { summary = "", details = {} }
    end
    data.details = data.details or {}
    data.summary = data.summary or ""
    return data
end

local bar = hs.menubar.new()
bar:setTitle("…")

local banner        = nil
local banner_key    = ""  -- tracks last rendered state to avoid needless redraws

local last_summary  = ""
local last_blocked  = 0
local blink_on      = true

local function render_title()
    if last_blocked == 0 then
        bar:setTitle(last_summary)
        return
    end
    local rest = last_summary:match("^🔔%d+(.*)$") or ""
    local blocked_part = "🔔" .. last_blocked
    local color = blink_on
        and { red = 1, green = 0.15, blue = 0.15, alpha = 1 }
        or  { red = 1, green = 1,    blue = 1,    alpha = 0.45 }
    local styled = hs.styledtext.new(blocked_part, {
        color = color,
        font  = { name = ".AppleSystemUIFont", size = 14 },
    }) .. hs.styledtext.new(rest, {
        font  = { name = ".AppleSystemUIFont", size = 14 },
    })
    bar:setTitle(styled)
end

local function focus_pane(pane)
    local tmux = "/opt/homebrew/bin/tmux -S /private/tmp/tmux-" .. UID .. "/default"
    local win = pane:match("^(.+)%.[^.]+$") or pane
    hs.execute(tmux .. " select-window -t '" .. win .. "' 2>/dev/null")
    hs.execute(tmux .. " select-pane -t '" .. pane .. "' 2>/dev/null")
    hs.application.launchOrFocus("iTerm")
end

local function update_banner(waiting_sessions)
    local n = #waiting_sessions

    -- Build a key to skip redraws when nothing changed
    local names = {}
    for _, s in ipairs(waiting_sessions) do names[#names+1] = s.project_name or "?" end
    local key = table.concat(names, "|")
    if key == banner_key then return end
    banner_key = key

    if banner then banner:delete(); banner = nil end
    if n == 0 then return end

    local lines = n + 1  -- header + one per session
    local h = BANNER_PAD * 2 + BANNER_LINE_H * lines + 4  -- 4 = gap after header

    local sf = hs.screen.mainScreen():frame()
    local x  = sf.x + sf.w - BANNER_W - BANNER_MARGIN
    local y  = sf.y + 28 + BANNER_MARGIN  -- below menubar

    banner = hs.canvas.new({ x = x, y = y, w = BANNER_W, h = h })
    banner:level(hs.canvas.windowLevels.overlay)
    banner:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
                  + hs.canvas.windowBehaviors.stationary)

    -- Background
    banner:appendElements({
        type            = "rectangle",
        action          = "fill",
        fillColor       = { red = 0.08, green = 0.08, blue = 0.1, alpha = 0.93 },
        roundedRectRadii = { xRadius = 10, yRadius = 10 },
        frame           = { x = 0, y = 0, w = BANNER_W, h = h },
    })

    -- Header: "🔔 2 waiting"
    banner:appendElements({
        type      = "text",
        text      = "🔔 " .. n .. " waiting",
        textColor = { red = 1, green = 0.72, blue = 0.2, alpha = 1 },
        textSize  = 13,
        textFont  = "Menlo",
        frame     = { x = BANNER_PAD, y = BANNER_PAD, w = BANNER_W - BANNER_PAD * 2, h = BANNER_LINE_H },
    })

    -- Session names
    for i, s in ipairs(waiting_sessions) do
        banner:appendElements({
            type      = "text",
            text      = "  " .. (s.project_name or "?"),
            textColor = { white = 1, alpha = 0.85 },
            textSize  = 12,
            textFont  = "Menlo",
            frame     = {
                x = BANNER_PAD,
                y = BANNER_PAD + BANNER_LINE_H + 4 + (i - 1) * BANNER_LINE_H,
                w = BANNER_W - BANNER_PAD * 2,
                h = BANNER_LINE_H,
            },
        })
    end

    banner:show()
end

local function refresh()
    local data = fetch_summary()
    local sessions = data.details

    local waiting = 0
    local waiting_sessions = {}
    for _, s in ipairs(sessions) do
        if s.status == "Input" then
            waiting = waiting + 1
            waiting_sessions[#waiting_sessions + 1] = s
        end
    end

    last_summary = data.summary
    last_blocked = waiting
    render_title()
    bar:setTooltip(#sessions .. " session(s) · " .. waiting .. " waiting")
    update_banner(waiting_sessions)

    local menu = {}
    for _, s in ipairs(sessions) do
        local icon = STATUS_ICON[s.status] or "❓"
        local sess = s
        local label = s.project_name or "?"
        if s.session_name then
            label = label .. " · " .. s.session_name
        elseif s.room_id then
            label = label .. " · " .. s.room_id
        end
        table.insert(menu, {
            title = icon .. " " .. label,
            fn = function() focus_pane(sess.pane_target) end,
        })
    end

    if #menu == 0 then
        table.insert(menu, { title = "No active sessions", disabled = true })
    else
        table.insert(menu, { title = "-" })
        table.insert(menu, {
            title    = #sessions .. " total · " .. waiting .. " waiting",
            disabled = true,
        })
    end

    bar:setMenu(menu)
end

local timer = hs.timer.doEvery(INTERVAL, refresh)
local blink_timer = hs.timer.doEvery(0.5, function()
    if last_blocked > 0 then
        blink_on = not blink_on
        render_title()
    elseif not blink_on then
        blink_on = true
        render_title()
    end
end)
refresh()

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "'", function()
    local frame = bar:frame()
    hs.eventtap.leftClick({ x = frame.x + frame.w / 2, y = frame.y + frame.h / 2 })
end)

M.refresh = refresh
return M
