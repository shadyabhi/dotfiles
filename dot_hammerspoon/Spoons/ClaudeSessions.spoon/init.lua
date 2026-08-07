--- === ClaudeSessions ===
---
--- Menubar widget for Claude/Codex session status. Polls a JSON-emitting script.
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
    bannerW       = 520,
    bannerYFrac   = 0.10,
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
        if s.age_tick then s.age_tick:stop() end
        if s.in_flight then pcall(function() s.in_flight:terminate() end) end
        if s.bar then s.bar:delete() end
        if s.banner then s.banner:hide() end
        if s.hotkey then s.hotkey:delete() end
        if s.caffeinate then pcall(function() s.caffeinate:terminate() end) end
    end
end

local function caffeinate_set(state, want)
    if state.caffeinate and not state.caffeinate:isRunning() then
        state.caffeinate = nil
    end
    if want and not state.caffeinate then
        local t = hs.task.new("/usr/bin/caffeinate", function()
            if _G._claude_sessions_state then
                _G._claude_sessions_state.caffeinate = nil
            end
        end, { "-di" })
        if t then t:start(); state.caffeinate = t end
    elseif (not want) and state.caffeinate then
        pcall(function() state.caffeinate:terminate() end)
        state.caffeinate = nil
    end
end

local function parse_and_apply(out, on_data)
    local ok, data = pcall(hs.json.decode, out or "")
    if not ok or type(data) ~= "table" then
        data = { summary = "🔔0 🤔0 💤0", details = {} }
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

    local function fmt_ago(ms)
        if not ms or type(ms) ~= "number" then return "?" end
        local secs = math.max(0, math.floor(os.time() - ms / 1000))
        if secs < 60 then return secs .. "s ago" end
        local mins = math.floor(secs / 60)
        if mins < 60 then return mins .. "m ago" end
        local hrs = math.floor(mins / 60)
        return string.format("%dh%02dm ago", hrs, mins % 60)
    end

    local function shorten_cwd(cwd)
        if not cwd then return "?" end
        local home = os.getenv("HOME") or ""
        if home ~= "" and cwd:sub(1, #home) == home then
            return "~" .. cwd:sub(#home + 1)
        end
        return cwd
    end

    local last_waiting = {}

    local function update_banner(waiting_sessions)
        last_waiting = waiting_sessions
        local n = #waiting_sessions
        local lines, key_parts = {}, {}
        for _, s in ipairs(waiting_sessions) do
            local cwd = shorten_cwd(s.cwd)
            local age = fmt_ago(s.started_at)
            local agent = s.agent or "Claude"
            lines[#lines+1] = agent .. "  ·  " .. cwd .. "  ·  started " .. age
            key_parts[#key_parts+1] = agent .. ":" .. (s.session_id or s.cwd or "?") .. "@" .. tostring(s.started_at or 0)
        end
        local key = table.concat(key_parts, "|")
        if key == banner_key then return end
        banner_key = key

        if n == 0 then
            if banner then banner:hide(); banner = nil; state.banner = nil end
            return
        end

        if not (spoon and spoon.Notify and spoon.Notify.show) then
            hs.printf("[ClaudeSessions] Notify spoon not loaded; skipping banner")
            return
        end

        local clickTargets = {}
        for i, s in ipairs(waiting_sessions) do clickTargets[i] = s.pane_target end
        local opts = {
            style     = "banner",
            level     = "alert",
            title     = "✴️ " .. n .. " waiting",
            rows      = lines,
            width     = theme.bannerW,
            yFraction = theme.bannerYFrac,
            onClick   = function(_, idx)
                local pane = clickTargets[idx]
                if pane then focus_pane(pane) end
            end,
        }
        if banner then
            banner:update(opts)
        else
            banner = spoon.Notify:show(opts)
        end
        state.banner = banner
    end

    local function apply_data(data)
        local sessions = data.details
        local waiting, waiting_sessions, working = 0, {}, 0
        for _, s in ipairs(sessions) do
            if s.status == "Input" then
                waiting = waiting + 1
                waiting_sessions[#waiting_sessions + 1] = s
            elseif s.status == "Working" then
                working = working + 1
            end
        end
        last_summary = data.summary
        last_blocked = waiting
        render_title()
        bar:setTooltip(#sessions .. " session(s) · " .. waiting .. " waiting")
        update_banner(waiting_sessions)
        caffeinate_set(state, working > 0)
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
            local agent = s.agent or "Claude"
            local label = agent .. " · " .. (s.project_name or "?")
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
        if not in_flight then
            state.in_flight = nil
            parse_and_apply("", apply_data)
            return
        end
        state.in_flight = in_flight
        local ok, started = pcall(function() return in_flight:start() end)
        if not ok or started == false then
            in_flight = nil
            state.in_flight = nil
            parse_and_apply("", apply_data)
        end
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

    local age_tick = hs.timer.doEvery(30, function()
        if banner and #last_waiting > 0 then
            banner_key = nil
            update_banner(last_waiting)
        end
    end)
    state.age_tick = age_tick

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
