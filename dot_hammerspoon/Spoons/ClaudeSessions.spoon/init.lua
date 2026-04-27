--- === ClaudeSessions ===
---
--- Menubar widget for Claude session status. Polls a JSON-emitting script.
--- Click menubar (or hotkey) opens chooser; selecting a session focuses its tmux pane in iTerm.

local obj = {}
obj.__index = obj

obj.name = "ClaudeSessions"
obj.version = "1.0"
obj.author = "Abhijeet Rastogi"
obj.license = "MIT"

obj.intervalSec = 1
obj.fetchTimeoutSec = 5
obj.terminalApp = "iTerm"

local HOME = os.getenv("HOME")
local UID = hs.execute("id -u 2>/dev/null"):gsub("%s+", "")

obj.script = nil
obj.tmuxSocket = "/private/tmp/tmux-" .. UID .. "/default"
obj.hotkey = nil

obj.theme = {
    bannerW       = 200,
    bannerPad     = 12,
    bannerLineH   = 18,
    bannerMargin  = 8,
    statusIcon    = { Input = "🔔", Working = "🤔", Idle = "💤" },
}

local state = {}

function obj:configure(opts)
    opts = opts or {}
    if opts.script then self.script = opts.script end
    if opts.intervalSec then self.intervalSec = opts.intervalSec end
    if opts.fetchTimeoutSec then self.fetchTimeoutSec = opts.fetchTimeoutSec end
    if opts.terminalApp then self.terminalApp = opts.terminalApp end
    if opts.tmuxSocket then self.tmuxSocket = opts.tmuxSocket end
    if opts.hotkey then self.hotkey = opts.hotkey end
    if opts.theme then
        for k, v in pairs(opts.theme) do self.theme[k] = v end
    end
    return self
end

local function teardown_prior()
    if _G._claude_sessions_state then
        local s = _G._claude_sessions_state
        if s.timer then s.timer:stop() end
        if s.blink_timer then s.blink_timer:stop() end
        if s.in_flight then pcall(function() s.in_flight:terminate() end) end
        if s.bar then s.bar:delete() end
        if s.banner then s.banner:delete() end
        if s.hotkey then s.hotkey:delete() end
    end
end

local function parse_and_apply(out, on_data)
    local ok, data = pcall(hs.json.decode, out or "")
    if not ok or type(data) ~= "table" then
        data = { summary = "", details = {} }
    end
    data.details = data.details or {}
    data.summary = data.summary or ""
    on_data(data)
end

function obj:start()
    if not self.script then
        self.script = self:_resource("menubar.py")
    end

    teardown_prior()
    state = {}
    _G._claude_sessions_state = state

    local theme = self.theme
    local in_flight, in_flight_started = nil, 0

    local bar = hs.menubar.new()
    bar:setTitle("…")
    state.bar = bar

    local banner, banner_key = nil, ""
    local last_summary, last_blocked = "", 0
    local blink_on, last_sessions = true, {}

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
        local tmux = "/opt/homebrew/bin/tmux -S " .. self.tmuxSocket
        local sess = pane:match("^([^:]+):") or ""
        local win  = pane:match("^(.+)%.[^.]+$") or pane
        if sess ~= "" then
            hs.execute(tmux .. " switch-client -t '" .. sess .. "' 2>/dev/null")
        end
        hs.execute(tmux .. " select-window -t '" .. win .. "' 2>/dev/null")
        hs.execute(tmux .. " select-pane -t '" .. pane .. "' 2>/dev/null")
        hs.application.launchOrFocus(self.terminalApp)
    end

    local function update_banner(waiting_sessions)
        local n = #waiting_sessions
        local names = {}
        for _, s in ipairs(waiting_sessions) do names[#names+1] = s.project_name or "?" end
        local key = table.concat(names, "|")
        if key == banner_key then return end
        banner_key = key

        if banner then banner:delete(); banner = nil end
        if n == 0 then return end

        local lines = n + 1
        local h = theme.bannerPad * 2 + theme.bannerLineH * lines + 4
        local sf = hs.screen.mainScreen():frame()
        local x  = sf.x + sf.w - theme.bannerW - theme.bannerMargin
        local y  = sf.y + 28 + theme.bannerMargin

        banner = hs.canvas.new({ x = x, y = y, w = theme.bannerW, h = h })
        state.banner = banner
        banner:level(hs.canvas.windowLevels.overlay)
        banner:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
                      + hs.canvas.windowBehaviors.stationary)
        banner:appendElements({
            type             = "rectangle",
            action           = "fill",
            fillColor        = { red = 0.08, green = 0.08, blue = 0.1, alpha = 0.93 },
            roundedRectRadii = { xRadius = 10, yRadius = 10 },
            frame            = { x = 0, y = 0, w = theme.bannerW, h = h },
        })
        banner:appendElements({
            type      = "text",
            text      = "🔔 " .. n .. " waiting",
            textColor = { red = 1, green = 0.72, blue = 0.2, alpha = 1 },
            textSize  = 13,
            textFont  = "Menlo",
            frame     = { x = theme.bannerPad, y = theme.bannerPad,
                          w = theme.bannerW - theme.bannerPad * 2, h = theme.bannerLineH },
        })
        for i, s in ipairs(waiting_sessions) do
            banner:appendElements({
                type      = "text",
                text      = "  " .. (s.project_name or "?"),
                textColor = { white = 1, alpha = 0.85 },
                textSize  = 12,
                textFont  = "Menlo",
                frame     = {
                    x = theme.bannerPad,
                    y = theme.bannerPad + theme.bannerLineH + 4 + (i - 1) * theme.bannerLineH,
                    w = theme.bannerW - theme.bannerPad * 2,
                    h = theme.bannerLineH,
                },
            })
        end
        banner:show()
    end

    local function apply_data(data)
        local sessions = data.details
        local waiting, waiting_sessions = 0, {}
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
            local icon = theme.statusIcon[s.status] or "❓"
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

    bar:setClickCallback(function() show_chooser() end)

    local function refresh()
        if in_flight then
            if hs.timer.secondsSinceEpoch() - in_flight_started > self.fetchTimeoutSec then
                pcall(function() in_flight:terminate() end)
                in_flight = nil
            else
                return
            end
        end
        in_flight_started = hs.timer.secondsSinceEpoch()
        in_flight = hs.task.new(self.script, function(_, stdout, _)
            in_flight = nil
            state.in_flight = nil
            parse_and_apply(stdout, apply_data)
        end)
        state.in_flight = in_flight
        in_flight:start()
    end
    self._refresh = refresh

    local timer = hs.timer.doEvery(self.intervalSec, refresh)
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

    if self.hotkey then
        state.hotkey = hs.hotkey.bind(self.hotkey[1], self.hotkey[2], show_chooser)
    end

    return self
end

function obj:_resource(name)
    return hs.spoons.resourcePath("scripts/" .. name)
end

function obj:refresh()
    if self._refresh then self._refresh() end
end

return obj
