--- === AgentSessions ===
---
--- Menubar widget for agent session status. Polls a JSON-emitting script.
--- Menubar click opens chooser; hotkey toggles canvas panel; panel auto-shows
--- when any session needs user input. Selecting a row focuses its tmux pane.

local obj = {}
obj.__index = obj

obj.name = "AgentSessions"
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
    statusIcon = { Input = "🔔", Working = "🤔", Idle = "💤" },
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
    local prior = _G._agent_sessions_state or _G._claude_sessions_state
    if prior then
        local s = prior
        if s.timer then s.timer:stop() end
        if s.blink_timer then s.blink_timer:stop() end
        if s.in_flight then pcall(function() s.in_flight:terminate() end) end
        if s.bar then s.bar:delete() end
        if s.hotkey then s.hotkey:delete() end
        for _, k in ipairs({ "panel_esc", "panel_up", "panel_down", "panel_enter", "panel_tab", "panel_shifttab" }) do
            if s[k] then s[k]:delete() end
        end
        if s.panel then s.panel:delete() end
        if s.caffeinate then pcall(function() s.caffeinate:terminate() end) end
    end
    _G._agent_sessions_state = nil
    _G._claude_sessions_state = nil
end

local function caffeinate_set(state, want)
    if state.caffeinate and not state.caffeinate:isRunning() then
        state.caffeinate = nil
    end
    if want and not state.caffeinate then
        local t = hs.task.new("/usr/bin/caffeinate", function()
            if _G._agent_sessions_state then
                _G._agent_sessions_state.caffeinate = nil
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
    _G._agent_sessions_state = state

    local theme = self.theme
    local in_flight, in_flight_started = nil, 0

    local bar = hs.menubar.new()
    bar:setTitle("…")
    state.bar = bar

    local last_summary, last_blocked = "", 0
    local blink_on, last_sessions = true, {}
    local panel_auto_shown, dismissed_waiting_key, last_waiting_key = false, nil, ""

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

    local function waiting_key_for(waiting_sessions)
        local parts = {}
        for _, s in ipairs(waiting_sessions) do
            parts[#parts+1] = (s.agent or "?") .. ":" .. (s.session_id or s.cwd or "?") .. "@" .. tostring(s.started_at or 0)
        end
        return table.concat(parts, "|")
    end

    local maybe_auto_panel  -- forward decl, defined after show_panel

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
        caffeinate_set(state, working > 0)
        last_sessions = sessions
        if maybe_auto_panel then maybe_auto_panel(waiting_sessions) end
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
            local agent = s.agent or "Agent"
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

    local panel = nil
    local panel_origin = nil

    local function hide_panel(reason)
        for _, k in ipairs({ "panel_esc", "panel_up", "panel_down", "panel_enter", "panel_tab", "panel_shifttab" }) do
            if state[k] then state[k]:delete(); state[k] = nil end
        end
        if panel then
            local ok, tl = pcall(function() return panel:topLeft() end)
            if ok and tl then panel_origin = tl end
            panel:delete(); panel = nil; state.panel = nil
        end
        if reason == "user_dismiss" then
            dismissed_waiting_key = last_waiting_key
        end
        panel_auto_shown = false
    end
    state.hide_panel = hide_panel

    local function show_panel(was_auto)
        local prev = panel
        local prev_tl = nil
        if prev then
            local ok, tl = pcall(function() return prev:topLeft() end)
            if ok and tl then prev_tl = tl end
        end
        for _, k in ipairs({ "panel_esc", "panel_up", "panel_down", "panel_enter", "panel_tab", "panel_shifttab" }) do
            if state[k] then state[k]:delete(); state[k] = nil end
        end
        if prev then prev:delete(); panel = nil; state.panel = nil end

        local order = { "Input", "Working", "Idle" }
        local headers = {
            Input   = { icon = "🔔", label = "Waiting for input", color = { red = 1.00, green = 0.55, blue = 0.30, alpha = 1 } },
            Working = { icon = "🤔", label = "Working",           color = { red = 0.45, green = 0.75, blue = 1.00, alpha = 1 } },
            Idle    = { icon = "💤", label = "Idle",              color = { white = 0.70, alpha = 1 } },
        }
        local groups = { Input = {}, Working = {}, Idle = {} }
        for _, s in ipairs(last_sessions) do
            local g = groups[s.status]
            if g then g[#g + 1] = s else groups.Idle[#groups.Idle + 1] = s end
        end
        local function age_key(s) return tonumber(s.started_at) or 0 end
        for _, k in ipairs(order) do
            table.sort(groups[k], function(a, b) return age_key(a) > age_key(b) end)
        end

        local pad, rowH, headerH, sectionGap, previewH = 16, 30, 28, 8, 22
        local W = 760
        local function has_preview(s)
            return s.status == "Input" and s.prompt_preview and s.prompt_preview ~= ""
        end
        local visible = {}
        local H = pad
        for _, k in ipairs(order) do
            if #groups[k] > 0 then
                visible[#visible + 1] = k
                H = H + headerH + sectionGap
                for _, s in ipairs(groups[k]) do
                    H = H + rowH + (has_preview(s) and previewH or 0)
                end
            end
        end
        if #visible == 0 then H = H + headerH end
        H = H + pad

        local sf = hs.screen.mainScreen():frame()
        local x = sf.x + (sf.w - W) / 2
        local y = sf.y + sf.h * 0.15
        if prev_tl then x, y = prev_tl.x, prev_tl.y
        elseif panel_origin then x, y = panel_origin.x, panel_origin.y end
        local c = hs.canvas.new({ x = x, y = y, w = W, h = H })
        c:level(hs.canvas.windowLevels.overlay)
        c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces + hs.canvas.windowBehaviors.stationary)

        c[1] = {
            type = "rectangle",
            id = "bg",
            trackMouseDown = true,
            roundedRectRadii = { xRadius = 10, yRadius = 10 },
            fillColor = { red = 0.10, green = 0.10, blue = 0.12, alpha = 0.96 },
            strokeColor = { red = 0.25, green = 0.25, blue = 0.28, alpha = 0.6 },
            strokeWidth = 0.5,
        }

        local rowPane, rowHiIdx = {}, {}
        local cursorY = pad

        if #visible == 0 then
            c[#c + 1] = {
                type = "text",
                text = "No active sessions",
                textColor = { white = 0.65 },
                textSize = 16,
                textFont = "Menlo",
                frame = { x = pad, y = cursorY + 4, w = W - 2 * pad, h = headerH },
            }
        end

        for _, k in ipairs(visible) do
            local hdr = headers[k]
            local list = groups[k]
            c[#c + 1] = {
                type = "text",
                text = hdr.icon .. "  " .. hdr.label .. "  (" .. #list .. ")",
                textColor = hdr.color,
                textSize = 14,
                textFont = "Menlo-Bold",
                frame = { x = pad, y = cursorY + 4, w = W - 2 * pad, h = headerH },
            }
            cursorY = cursorY + headerH
            for _, s in ipairs(list) do
                local rowIdx = #rowPane + 1
                rowPane[rowIdx] = s.pane_target
                local thisH = rowH + (has_preview(s) and previewH or 0)
                local hi = #c + 1
                c[hi] = {
                    type = "rectangle",
                    id = "row_" .. rowIdx,
                    action = "fill",
                    trackMouseDown = true,
                    trackMouseEnterExit = true,
                    frame = { x = pad - 6, y = cursorY, w = W - 2 * (pad - 6), h = thisH },
                    roundedRectRadii = { xRadius = 6, yRadius = 6 },
                    fillColor = { white = 1, alpha = 0 },
                    strokeWidth = 0,
                }
                rowHiIdx[rowIdx] = hi

                local agent = s.agent or "Agent"
                local proj  = s.project_name or "?"
                local name  = s.session_name or s.room_id or ""
                local left  = "  " .. agent .. " · " .. proj
                if name ~= "" then left = left .. " · " .. name end
                local right = (s.model_display or "?") .. " · " .. (s.context_display or "?") .. " · " .. fmt_ago(s.started_at) .. "  "

                c[#c + 1] = {
                    type = "text",
                    id = "rowL_" .. rowIdx,
                    trackMouseDown = true,
                    trackMouseEnterExit = true,
                    text = left,
                    textColor = { white = 0.92 },
                    textSize = 14,
                    textFont = "Menlo",
                    frame = { x = pad, y = cursorY + 6, w = W * 0.55, h = rowH - 8 },
                }
                c[#c + 1] = {
                    type = "text",
                    id = "rowR_" .. rowIdx,
                    trackMouseDown = true,
                    trackMouseEnterExit = true,
                    text = right,
                    textColor = { white = 0.60 },
                    textSize = 13,
                    textFont = "Menlo",
                    textAlignment = "right",
                    frame = { x = W * 0.55, y = cursorY + 7, w = W * 0.45 - pad, h = rowH - 8 },
                }
                if has_preview(s) then
                    c[#c + 1] = {
                        type = "text",
                        id = "rowP_" .. rowIdx,
                        trackMouseDown = true,
                        trackMouseEnterExit = true,
                        text = "  ↳ " .. s.prompt_preview,
                        textColor = { red = 1.00, green = 0.80, blue = 0.55, alpha = 0.85 },
                        textSize = 12,
                        textFont = "Menlo",
                        frame = { x = pad + 4, y = cursorY + rowH - 2, w = W - 2 * pad - 4, h = previewH },
                    }
                end
                cursorY = cursorY + thisH
            end
            cursorY = cursorY + sectionGap
        end

        local total = #rowPane
        local selected = total > 0 and 1 or 0

        local function paint(i, on)
            local hi = rowHiIdx[i]
            if not hi then return end
            c[hi].fillColor = on and { white = 1, alpha = 0.16 } or { white = 1, alpha = 0 }
        end
        local function set_selected(i)
            if i < 1 or i > total or i == selected then return end
            paint(selected, false)
            selected = i
            paint(selected, true)
        end
        paint(selected, true)

        local function activate()
            if selected < 1 then hide_panel(); return end
            local pane = rowPane[selected]
            hide_panel("user_dismiss")
            if pane then focus_pane(pane) end
        end

        c:mouseCallback(function(_, evt, elemId)
            if type(elemId) ~= "string" then return end
            local idx = tonumber(elemId:match("^row[LRP]?_(%d+)$"))
            if idx then
                if evt == "mouseEnter" then
                    set_selected(idx)
                elseif evt == "mouseDown" then
                    set_selected(idx)
                    activate()
                end
            elseif elemId == "bg" and evt == "mouseDown" then
                hide_panel("user_dismiss")
            end
        end)

        c:show()
        panel = c
        state.panel = c
        panel_auto_shown = was_auto and true or false
        state.panel_esc       = hs.hotkey.bind({}, "escape", function() hide_panel("user_dismiss") end)
        state.panel_up        = hs.hotkey.bind({}, "up",     function() set_selected(selected - 1) end)
        state.panel_down      = hs.hotkey.bind({}, "down",   function() set_selected(selected + 1) end)
        state.panel_enter     = hs.hotkey.bind({}, "return", activate)
        state.panel_tab       = hs.hotkey.bind({}, "tab",    function() set_selected(selected % math.max(1, total) + 1) end)
        state.panel_shifttab  = hs.hotkey.bind({ "shift" }, "tab", function() set_selected((selected - 2) % math.max(1, total) + 1) end)
    end

    local function toggle_panel()
        if panel then
            hide_panel("user_dismiss")
        else
            dismissed_waiting_key = nil
            show_panel(false)
        end
    end
    state.toggle_panel = toggle_panel

    maybe_auto_panel = function(waiting_sessions)
        local key = waiting_key_for(waiting_sessions)
        local prev_key = last_waiting_key
        last_waiting_key = key
        if #waiting_sessions == 0 then
            if panel and panel_auto_shown then hide_panel() end
            dismissed_waiting_key = nil
            return
        end
        if panel then
            if key ~= prev_key then show_panel(panel_auto_shown) end
            return
        end
        if key == dismissed_waiting_key then return end
        show_panel(true)
    end

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

    refresh()

    if self.hotkey then
        state.hotkey = hs.hotkey.bind(self.hotkey[1], self.hotkey[2], toggle_panel)
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
