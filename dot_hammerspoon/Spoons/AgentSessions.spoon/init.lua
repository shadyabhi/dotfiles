--- === AgentSessions ===
---
--- Menubar (system tray) widget for agent session status. Polls a
--- JSON-emitting script. The title shows only non-zero status counts.
--- Menubar click and hotkey both toggle the canvas panel; the panel also
--- auto-shows when any session needs user input. Selecting a row focuses its
--- tmux pane.
---
--- By default a session needing input is focused directly and the panel is not
--- shown at all; the panel is then only reachable by hotkey or tray click. A
--- toggle at its bottom turns that off, restoring the auto-popup. The choice
--- persists across reloads in hs.settings.

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
local log = hs.logger.new("AgentSessions", "info")

obj.script = nil
obj.tmuxSocket = "/private/tmp/tmux-" .. UID .. "/default"
obj.hotkey = nil

local state = {}

-- Hotkeys that live only while the panel is open. Bound in show_panel, dropped
-- in hide_panel, and swept by teardown_prior after a config reload.
local PANEL_KEYS = {
    "panel_esc", "panel_up", "panel_down",
    "panel_enter", "panel_tab", "panel_shifttab", "panel_f",
}

local SETTING_AUTO_FOCUS = "AgentSessions.autoFocus"

-- Focus the lone waiting session instead of popping the panel. Defaults on:
-- an unset key is not the same as an explicit false.
local function auto_focus_enabled()
    local v = hs.settings.get(SETTING_AUTO_FOCUS)
    if v == nil then return true end
    return v and true or false
end

function obj:configure(opts)
    opts = opts or {}
    if opts.script then self.script = opts.script end
    if opts.intervalSec then self.intervalSec = opts.intervalSec end
    if opts.fetchTimeoutSec then self.fetchTimeoutSec = opts.fetchTimeoutSec end
    if opts.terminalApp then self.terminalApp = opts.terminalApp end
    if opts.tmuxSocket then self.tmuxSocket = opts.tmuxSocket end
    if opts.hotkey then self.hotkey = opts.hotkey end
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
        for _, k in ipairs(PANEL_KEYS) do
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
    -- A transient empty/truncated read (startup race, timeout) should keep the
    -- last good state rather than blanking the widget to zeros or logging a
    -- JSON error. A genuine "no sessions" result is still valid JSON, not empty.
    if not out or out:match("^%s*$") then return end
    local ok, data = pcall(hs.json.decode, out)
    if not ok or type(data) ~= "table" then return end
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

    local in_flight, in_flight_started = nil, 0

    local bar = hs.menubar.new()
    bar:setTitle("…")
    state.bar = bar

    local last_blocked, last_working, last_idle = 0, 0, 0
    local blink_on, last_sessions = true, {}
    local panel_auto_shown = false
    local dismissed_tokens = {}   -- per-question tokens the user dismissed and that are still pending
    local waiting_now = {}        -- tokens of sessions waiting on the latest refresh (for dismiss bookkeeping)
    local last_sig = ""           -- signature of the waiting set, to detect changes

    -- Concise title: only non-zero counts appear, in 🔔/🤔/💤 priority order.
    -- The 🔔 segment blinks red↔dim while any session is blocked. When nothing
    -- is running, waiting, or idle, collapse to a single 💤 so the tray icon
    -- never goes blank.
    local function render_title()
        local font = { name = ".AppleSystemUIFont", size = 14 }
        if last_blocked == 0 and last_working == 0 and last_idle == 0 then
            bar:setTitle(hs.styledtext.new("💤", { font = font }))
            return
        end
        local title = nil
        local function append(st)
            title = title and (title .. hs.styledtext.new(" ", { font = font }) .. st) or st
        end
        if last_blocked > 0 then
            local color = blink_on
                and { red = 1, green = 0.15, blue = 0.15, alpha = 1 }
                or  { red = 1, green = 1,    blue = 1,    alpha = 0.45 }
            append(hs.styledtext.new("🔔" .. last_blocked, { color = color, font = font }))
        end
        if last_working > 0 then
            append(hs.styledtext.new("🤔" .. last_working, { font = font }))
        end
        if last_idle > 0 then
            append(hs.styledtext.new("💤" .. last_idle, { font = font }))
        end
        bar:setTitle(title)
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

    -- True when the user is already looking at this tmux pane: it is the active
    -- pane of the active window in an attached session, AND the terminal app is
    -- frontmost. Used to skip the auto-popup when the session is already visible.
    local function pane_is_active(pane)
        if not pane then return false end
        local front = hs.application.frontmostApplication()
        if not front or front:name() ~= self.terminalApp then return false end
        local tmux = "/opt/homebrew/bin/tmux -S " .. self.tmuxSocket
        local fmt = "#{session_attached}:#{window_active}:#{pane_active}"
        local out = hs.execute(tmux .. " display-message -p -t '" .. pane
            .. "' '" .. fmt .. "' 2>/dev/null") or ""
        local att, win, pn = out:match("(%d+):(%d+):(%d+)")
        return att ~= nil and tonumber(att) > 0 and win == "1" and pn == "1"
    end

    -- Non-tmux sessions (e.g. Claude in IntelliJ's or VS Code's built-in
    -- terminal) have no pane to switch to: the shell runs as a descendant of
    -- the host GUI app, so walk the process tree up from the session's pid
    -- until a pid resolves to a running application, then raise it.
    -- Map running app pids once. hs.application.applicationForPID logs a console
    -- error for every non-app pid, and a process-tree walk hits several before
    -- reaching the host app; a membership check against this map stays quiet.
    local function running_app_map()
        local appByPid = {}
        for _, a in ipairs(hs.application.runningApplications()) do
            appByPid[a:pid()] = a
        end
        return appByPid
    end

    -- Non-tmux sessions (e.g. Claude in IntelliJ's or VS Code's built-in
    -- terminal) have no pane to switch to: the shell runs as a descendant of the
    -- host GUI app. Walk the process tree up from pid until one resolves to a
    -- running application.
    local function app_for_pid(pid, appByPid)
        pid = tonumber(pid)
        local seen = {}
        while pid and pid > 1 and not seen[pid] do
            seen[pid] = true
            if appByPid[pid] then return appByPid[pid] end
            local out = hs.execute("/bin/ps -o ppid= -p " .. pid .. " 2>/dev/null")
            pid = tonumber((out or ""):match("%d+"))
        end
        return nil
    end

    local function focus_app_for_pid(pid)
        local app = app_for_pid(pid, running_app_map())
        if app then app:activate(true) end
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

    -- A per-question identity for a waiting session. updated_at changes only when
    -- the session takes a new turn (Claude freezes it while waiting and bumps it on
    -- the next question), so dismissing one question never suppresses the next one.
    local function session_token(s)
        return (s.agent or "?") .. ":" .. (s.session_id or s.cwd or "?")
            .. "@" .. tostring(s.updated_at or s.started_at or 0)
    end

    local panel = nil
    local maybe_auto_panel  -- forward decl, defined after show_panel
    local toggle_panel      -- forward decl, defined after show_panel

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
        last_blocked = waiting
        last_working = working
        last_idle = math.max(0, #sessions - waiting - working)
        render_title()
        bar:setTooltip(#sessions .. " session(s) · " .. waiting .. " waiting")
        caffeinate_set(state, working > 0)
        last_sessions = sessions
        if maybe_auto_panel then maybe_auto_panel(waiting_sessions) end
    end

    -- Click the tray icon to toggle the detail panel (defined below). The panel
    -- also auto-shows when a session needs input and via the optional hotkey.
    bar:setClickCallback(function()
        if toggle_panel then toggle_panel() end
    end)

    local function hide_panel(reason)
        for _, k in ipairs(PANEL_KEYS) do
            if state[k] then state[k]:delete(); state[k] = nil end
        end
        if panel then
            panel:delete(); panel = nil; state.panel = nil
        end
        if reason == "user_dismiss" then
            for _, tok in ipairs(waiting_now) do dismissed_tokens[tok] = true end
        end
        panel_auto_shown = false
    end
    state.hide_panel = hide_panel

    local function show_panel(was_auto)
        local prev = panel
        for _, k in ipairs(PANEL_KEYS) do
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

        local pad, rowH, headerH, sectionGap, previewH = 28, 48, 44, 14, 34
        local toggleH, toggleGap = 34, 18
        local function has_preview(s)
            return s.status == "Input" and s.prompt_preview and s.prompt_preview ~= ""
        end
        local visible = {}
        local contentH = pad
        for _, k in ipairs(order) do
            if #groups[k] > 0 then
                visible[#visible + 1] = k
                contentH = contentH + headerH + sectionGap
                for _, s in ipairs(groups[k]) do
                    contentH = contentH + rowH + (has_preview(s) and previewH or 0)
                end
            end
        end
        if #visible == 0 then contentH = contentH + headerH end
        contentH = contentH + toggleGap + toggleH + pad

        -- Centred on the active screen. frame() (unlike fullFrame()) already
        -- excludes the menubar, so the result never rides under it.
        local sf = hs.screen.mainScreen():frame()
        local W = math.min(680, sf.w - 44)
        local H = math.min(math.max(contentH, 190), math.floor(sf.h * 0.72))
        local x = sf.x + math.floor((sf.w - W) / 2)
        local y = sf.y + math.floor((sf.h - H) / 2)
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

        local rowPane, rowPid, rowHiIdx, rowCount = {}, {}, {}, 0
        local cursorY = math.max(pad, math.floor((H - contentH) / 2))

        -- Host-app icon per row: tmux sessions live under the terminal app;
        -- non-tmux sessions resolve via the process-tree walk. Cache by bundle id
        -- so repeated lookups (and the same app across rows) cost one fetch.
        local appByPid = running_app_map()
        local termApp = hs.application.find(self.terminalApp)
        local iconCache = {}
        local function host_icon(s)
            local app = s.pane_target and termApp or app_for_pid(s.pid, appByPid)
            local bid = app and app:bundleID()
            if not bid then return nil end
            if iconCache[bid] == nil then
                iconCache[bid] = hs.image.imageFromAppBundle(bid) or false
            end
            return iconCache[bid] or nil
        end

        if #visible == 0 then
            c[#c + 1] = {
                type = "text",
                text = "No active sessions",
                textColor = { white = 0.65 },
                textSize = 24,
                textFont = "Menlo",
                frame = { x = pad, y = cursorY + 6, w = W - 2 * pad, h = headerH },
            }
        end

        for _, k in ipairs(visible) do
            local hdr = headers[k]
            local list = groups[k]
            c[#c + 1] = {
                type = "text",
                text = hdr.icon .. "  " .. hdr.label .. "  (" .. #list .. ")",
                textColor = hdr.color,
                textSize = 22,
                textFont = "Menlo-Bold",
                frame = { x = pad, y = cursorY + 8, w = W - 2 * pad, h = headerH },
            }
            cursorY = cursorY + headerH
            for _, s in ipairs(list) do
                -- Count rows explicitly: a non-tmux session has a nil pane_target,
                -- and `rowPane[#rowPane+1] = nil` is a no-op that would leave the
                -- array empty, making `total` 0. Store `false` as a dense
                -- placeholder so every visible row is selectable and dismissible.
                rowCount = rowCount + 1
                local rowIdx = rowCount
                rowPane[rowIdx] = s.pane_target or false
                rowPid[rowIdx] = s.pid
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
                local left  = agent .. " · " .. proj
                if name ~= "" then left = left .. " · " .. name end
                local right = (s.model_display or "?") .. " · " .. (s.context_display or "?") .. " · " .. fmt_ago(s.started_at) .. "  "

                -- Host-app icon, then text offset to clear it. Non-interactive:
                -- without a tracking flag the click falls through to the row rect.
                local iconSz, iconGap = 32, 12
                local textX = pad + iconSz + iconGap
                local icon = host_icon(s)
                if icon then
                    c[#c + 1] = {
                        type = "image",
                        image = icon,
                        imageScaling = "scaleProportionally",
                        frame = { x = pad, y = cursorY + (rowH - iconSz) / 2, w = iconSz, h = iconSz },
                    }
                end

                c[#c + 1] = {
                    type = "text",
                    id = "rowL_" .. rowIdx,
                    trackMouseDown = true,
                    trackMouseEnterExit = true,
                    text = left,
                    textColor = { white = 0.92 },
                    textSize = 20,
                    textFont = "Menlo",
                    frame = { x = textX, y = cursorY + 11, w = W * 0.55 - (textX - pad), h = rowH - 8 },
                }
                c[#c + 1] = {
                    type = "text",
                    id = "rowR_" .. rowIdx,
                    trackMouseDown = true,
                    trackMouseEnterExit = true,
                    text = right,
                    textColor = { white = 0.60 },
                    textSize = 18,
                    textFont = "Menlo",
                    textAlignment = "right",
                    frame = { x = W * 0.55, y = cursorY + 13, w = W * 0.45 - pad, h = rowH - 8 },
                }
                if has_preview(s) then
                    c[#c + 1] = {
                        type = "text",
                        id = "rowP_" .. rowIdx,
                        trackMouseDown = true,
                        trackMouseEnterExit = true,
                        text = "  ↳ " .. s.prompt_preview,
                        textColor = { red = 1.00, green = 0.80, blue = 0.55, alpha = 0.85 },
                        textSize = 16,
                        textFont = "Menlo",
                        frame = { x = pad + 4, y = cursorY + rowH - 2, w = W - 2 * pad - 4, h = previewH },
                    }
                end
                cursorY = cursorY + thisH
            end
            cursorY = cursorY + sectionGap
        end

        -- Settings row, pinned to the panel's bottom edge rather than appended to
        -- the content flow: when more sessions are listed than H can fit, the
        -- rows overflow but the toggle stays reachable.
        local toggleY = H - pad - toggleH
        c[#c + 1] = {
            type = "rectangle",
            action = "fill",
            frame = { x = pad, y = toggleY - math.floor(toggleGap / 2), w = W - 2 * pad, h = 1 },
            fillColor = { white = 1, alpha = 0.12 },
            strokeWidth = 0,
        }
        local toggleIdx = #c + 1
        c[toggleIdx] = {
            type = "rectangle",
            id = "toggle_bg",
            action = "fill",
            trackMouseDown = true,
            trackMouseEnterExit = true,
            frame = { x = pad - 6, y = toggleY, w = W - 2 * (pad - 6), h = toggleH },
            roundedRectRadii = { xRadius = 6, yRadius = 6 },
            fillColor = { white = 1, alpha = 0 },
            strokeWidth = 0,
        }
        local toggleTxtIdx = #c + 1
        c[toggleTxtIdx] = {
            type = "text",
            id = "toggle_txt",
            trackMouseDown = true,
            trackMouseEnterExit = true,
            text = "",
            textSize = 17,
            textFont = "Menlo",
            frame = { x = pad, y = toggleY + 8, w = W - 2 * pad, h = toggleH },
        }

        -- Repaint just this element rather than rebuilding the panel: tearing the
        -- canvas down and back up leaves the outgoing copy drawn on top for a
        -- beat, so the label appears not to have changed at all.
        local function render_toggle()
            local on = auto_focus_enabled()
            c[toggleTxtIdx].text = (on and "[✓]" or "[ ]") .. "  Auto-focus waiting session   (f)"
            c[toggleTxtIdx].textColor = on and { red = 0.55, green = 0.85, blue = 0.55, alpha = 1 }
                                            or { white = 0.55, alpha = 1 }
        end
        render_toggle()

        local function flip_auto_focus()
            hs.settings.set(SETTING_AUTO_FOCUS, not auto_focus_enabled())
            render_toggle()
        end

        local total = rowCount
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
            local pid = rowPid[selected]
            hide_panel("user_dismiss")
            if pane then focus_pane(pane) else focus_app_for_pid(pid) end
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
            elseif elemId:match("^toggle_") then
                if evt == "mouseEnter" then
                    c[toggleIdx].fillColor = { white = 1, alpha = 0.16 }
                elseif evt == "mouseExit" then
                    c[toggleIdx].fillColor = { white = 1, alpha = 0 }
                elseif evt == "mouseDown" then
                    flip_auto_focus()
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
        state.panel_f         = hs.hotkey.bind({}, "f", flip_auto_focus)
    end

    toggle_panel = function()
        if panel then
            hide_panel("user_dismiss")
        else
            show_panel(false)
        end
    end
    state.toggle_panel = toggle_panel

    maybe_auto_panel = function(waiting_sessions)
        -- Same waiting set the 🔔 count is built from; key each entry per-question.
        local cur, tokens, sess_by_tok = {}, {}, {}
        for _, s in ipairs(waiting_sessions) do
            local tok = session_token(s)
            cur[tok] = true
            tokens[#tokens + 1] = tok
            sess_by_tok[tok] = s
        end
        waiting_now = tokens
        -- Drop dismissals for questions that are no longer pending, so the next
        -- question (a fresh token) re-arms the popup on its own.
        for tok in pairs(dismissed_tokens) do
            if not cur[tok] then dismissed_tokens[tok] = nil end
        end

        local sig = table.concat(tokens, "|")
        local changed = sig ~= last_sig
        last_sig = sig

        if #waiting_sessions == 0 then
            if panel and panel_auto_shown then hide_panel() end
            return
        end

        local unseen = false
        for _, tok in ipairs(tokens) do
            if not dismissed_tokens[tok] then unseen = true; break end
        end

        if not panel then
            if unseen then
                -- First question still needing attention: undismissed, and not
                -- already on-screen in a focused pane. Each check costs a tmux
                -- round-trip, so stop at the first hit.
                local pending = nil
                for _, tok in ipairs(tokens) do
                    if not dismissed_tokens[tok] and not pane_is_active(sess_by_tok[tok].pane_target) then
                        pending = tok
                        break
                    end
                end
                if not pending then
                    if changed then log.i("waiting session already active; skipping popup") end
                elseif auto_focus_enabled() then
                    -- Go straight to the session; the panel never auto-opens. Only
                    -- on a change of the waiting set, and marking the token
                    -- dismissed, so focus is grabbed once per question instead of
                    -- once per poll or bouncing between two waiting sessions.
                    if changed then
                        local s = sess_by_tok[pending]
                        dismissed_tokens[pending] = true
                        if s.pane_target then focus_pane(s.pane_target) else focus_app_for_pid(s.pid) end
                    end
                else
                    show_panel(true)                   -- new/undismissed question: auto-pop
                end
            end
        elseif changed then
            show_panel(unseen and true or panel_auto_shown)  -- keep an open panel current
        end
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
        -- Accumulate stdout via a streaming reader. The completion-only form of
        -- hs.task lets the ~64KB OS pipe fill and then deadlocks (the completion
        -- callback never fires), and this script's output exceeds that as soon as
        -- a handful of sessions are listed. Read every chunk, then parse the join.
        local chunks = {}
        in_flight = hs.task.new(
            self.script,
            function(_, _, _)
                in_flight = nil
                state.in_flight = nil
                parse_and_apply(table.concat(chunks), apply_data)
            end,
            function(_, stdout, _)
                if stdout and #stdout > 0 then chunks[#chunks + 1] = stdout end
                return true
            end
        )
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
