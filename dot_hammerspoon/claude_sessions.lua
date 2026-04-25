local M = {}

local INTERVAL = 1
local FETCH_TIMEOUT = 5  -- seconds; kill menubar.py if it hangs
local HOME = os.getenv("HOME")
local UID = hs.execute("id -u 2>/dev/null"):gsub("%s+", "")

local STATUS_ICON = { Input = "🔔", Working = "🤔", Idle = "💤" }

local BANNER_W      = 200
local BANNER_PAD    = 12
local BANNER_LINE_H = 18
local BANNER_MARGIN = 8

local MENUBAR_PY = HOME .. "/scripts/claude/menubar.py"

-- Clean up any prior instance (Hammerspoon reload leaks closures otherwise)
if _G._claude_sessions_state then
    local s = _G._claude_sessions_state
    if s.timer then s.timer:stop() end
    if s.blink_timer then s.blink_timer:stop() end
    if s.in_flight then pcall(function() s.in_flight:terminate() end) end
    if s.bar then s.bar:delete() end
    if s.banner then s.banner:delete() end
    if s.hotkey then s.hotkey:delete() end
end
local state = {}
_G._claude_sessions_state = state

local in_flight = nil       -- hs.task currently running, or nil
local in_flight_started = 0 -- epoch seconds when current task started

local function parse_and_apply(out, on_data)
    local ok, data = pcall(hs.json.decode, out or "")
    if not ok or type(data) ~= "table" then
        data = { summary = "", details = {} }
    end
    data.details = data.details or {}
    data.summary = data.summary or ""
    on_data(data)
end

local bar = hs.menubar.new()
bar:setTitle("…")
state.bar = bar
bar:setClickCallback(function() if state.show_chooser then state.show_chooser() end end)

local banner        = nil
local banner_key    = ""  -- tracks last rendered state to avoid needless redraws

local last_summary  = ""
local last_blocked  = 0
local blink_on      = true
local last_sessions = {}

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
    state.banner = banner
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

local function apply_data(data)
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

    last_sessions = sessions
end

local chooser = hs.chooser.new(function(choice)
    if choice and choice.pane_target then focus_pane(choice.pane_target) end
end)
chooser:searchSubText(true)
state.chooser = chooser

local function show_chooser()
    local choices = {}
    for _, s in ipairs(last_sessions) do
        local icon = STATUS_ICON[s.status] or "❓"
        local label = s.project_name or "?"
        if s.session_name then
            label = label .. " · " .. s.session_name
        elseif s.room_id then
            label = label .. " · " .. s.room_id
        end
        local sub = (s.status or "") .. " · " .. (s.model_display or "") .. " · " .. (s.context_display or "")
        choices[#choices + 1] = {
            text        = icon .. " " .. label,
            subText     = sub,
            pane_target = s.pane_target,
        }
    end
    if #choices == 0 then
        choices[1] = { text = "No active sessions", subText = "" }
    end
    chooser:choices(choices)
    chooser:show()
end
state.show_chooser = show_chooser

local function refresh()
    -- If a previous task is still running, check timeout and skip this tick.
    if in_flight then
        if hs.timer.secondsSinceEpoch() - in_flight_started > FETCH_TIMEOUT then
            pcall(function() in_flight:terminate() end)
            in_flight = nil
        else
            return
        end
    end

    in_flight_started = hs.timer.secondsSinceEpoch()
    in_flight = hs.task.new(MENUBAR_PY, function(_, stdout, _)
        in_flight = nil
        state.in_flight = nil
        parse_and_apply(stdout, apply_data)
    end)
    state.in_flight = in_flight
    in_flight:start()
end

local timer = hs.timer.doEvery(INTERVAL, refresh)
state.timer = timer
local blink_timer = hs.timer.doEvery(0.5, function()
    if last_blocked > 0 then
        blink_on = not blink_on
        render_title()
    elseif not blink_on then
        blink_on = true
        render_title()
    end
end)
state.blink_timer = blink_timer
refresh()

state.hotkey = hs.hotkey.bind({"cmd", "alt", "ctrl"}, "'", show_chooser)

M.refresh = refresh
return M
