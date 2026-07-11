--- === Pomodoro ===
---
--- Lightweight Pomodoro starter and sticky progress banner.
---
--- Usage:
---     hs.loadSpoon("Pomodoro")
---     spoon.Pomodoro
---         :configure({ hotkey = { { "cmd", "alt", "ctrl" }, "p" } })
---         :start()

local obj = {}
obj.__index = obj

obj.name = "Pomodoro"
obj.version = "1.0"
obj.author = "Abhijeet Rastogi"
obj.license = "MIT"

obj.hotkey = { { "cmd", "alt", "ctrl" }, "p" }
obj.width = 460
obj.height = 92
obj.inputWidth = 420
obj.inputHeight = 514
obj.updateIntervalSec = 1
obj.completeSound = nil
obj.guardIntervalSec = 1

-- Apps whose open windows/tabs start pre-checked (implicitly selected) in the picker.
obj.autoSelectApps = { Obsidian = true }

obj._hotkey = nil
obj._webview = nil
obj._canvas = nil
obj._timer = nil
obj._finishAt = nil
obj._startedAt = nil
obj._durationSec = nil
obj._title = nil
obj._dragTap = nil
obj._allowedKeys = nil
obj._guardTimer = nil
obj._flashCanvas = nil
obj._distractedSec = 0

-- hs.settings key under which a running timer is persisted, so it survives a
-- Hammerspoon reload/restart.
local SETTINGS_KEY = "spoon.Pomodoro.state"

local function activeScreen()
    local fw = hs.window.focusedWindow()
    return (fw and fw:screen()) or hs.screen.mainScreen()
end

local function frameBelowNotch(w, h)
    local f = activeScreen():frame()
    return {
        x = f.x + math.floor((f.w - w) / 2),
        y = f.y + 8,
        w = w,
        h = h,
    }
end

-- Apply the shared overlay stacking + all-spaces behavior to a canvas or webview.
local function applyOverlay(surface)
    surface:level(hs.canvas.windowLevels.overlay)
    surface:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
        + hs.canvas.windowBehaviors.stationary)
    return surface
end

-- Stable focus-target keys, shared by the picker (listItems) and the focus guard
-- (_currentKey) so both sides encode windows/tabs identically.
local function keyForWindow(win)
    local id = win:id()
    return id and ("win:" .. tostring(id)) or nil
end

local function keyForTabUrl(url)
    return "tab:" .. url
end

local function trim(str)
    return tostring(str or ""):match("^%s*(.-)%s*$")
end

local function urlDecode(str)
    str = tostring(str or "")
    str = str:gsub("+", " ")
    return (str:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function parseQuery(url)
    local params = {}
    local query = tostring(url or ""):match("%?(.*)$")
    if not query then return params end
    query = query:match("^([^#]*)") or query

    for pair in query:gmatch("[^&]+") do
        local key, value = pair:match("^([^=]*)=?(.*)$")
        if key and key ~= "" then
            params[urlDecode(key)] = urlDecode(value or "")
        end
    end
    return params
end

local function fmtRemaining(sec)
    sec = math.max(0, math.floor(sec + 0.5))
    return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

-- Browsers we can introspect via AppleScript, mapped to their scripting dialect.
-- "safari" uses `current tab`; "chrome" (Chromium family) uses `active tab`.
local BROWSERS = {
    ["Safari"] = "safari",
    ["Safari Technology Preview"] = "safari",
    ["Google Chrome"] = "chrome",
    ["Google Chrome Canary"] = "chrome",
    ["Brave Browser"] = "chrome",
    ["Microsoft Edge"] = "chrome",
    ["Vivaldi"] = "chrome",
    ["Chromium"] = "chrome",
    ["Arc"] = "chrome",
}

-- URL of the frontmost window's active tab, or nil if unavailable.
local function activeTabUrl(appName)
    local style = BROWSERS[appName]
    if not style then return nil end
    local tabRef = (style == "safari") and "current tab" or "active tab"
    local script = string.format([[
        tell application "%s"
            if (count of windows) is 0 then return ""
            return URL of %s of front window
        end tell
    ]], appName, tabRef)
    local ok, res = hs.osascript.applescript(script)
    if ok and type(res) == "string" and res ~= "" then return res end
    return nil
end

-- All open tabs across every running supported browser: { app, title, url }.
local function listBrowserTabs()
    local out = {}
    for _, app in ipairs(hs.application.runningApplications()) do
        local name = app:name()
        local style = BROWSERS[name]
        if style then
            local titleProp = (style == "safari") and "name" or "title"
            -- Field separator is a unit separator (char 31); AppleScript's `tab`
            -- constant serializes as the literal text "tab" here, not a tab char.
            local script = string.format([[
                set out to {}
                tell application "%s"
                    repeat with w in windows
                        repeat with t in tabs of w
                            try
                                set end of out to (%s of t) & (character id 31) & (URL of t)
                            end try
                        end repeat
                    end repeat
                end tell
                set AppleScript's text item delimiters to linefeed
                return out as text
            ]], name, titleProp)
            local ok, res = hs.osascript.applescript(script)
            if ok and type(res) == "string" then
                for line in (res .. "\n"):gmatch("(.-)\n") do
                    local title, url = line:match("^(.-)" .. string.char(31) .. "(.*)$")
                    if url and url ~= "" then
                        out[#out + 1] = {
                            app = name,
                            title = (title and title ~= "") and title or url,
                            url = url,
                        }
                    end
                end
            end
        end
    end
    return out
end

-- Selectable focus targets for the dialog: non-browser windows plus browser tabs.
-- Each item carries a stable `key`: "win:<id>" for windows, "tab:<url>" for tabs.
local function listItems()
    local items = {}
    -- orderedWindows() is front-to-back z-order, i.e. most-recently-focused first.
    for _, w in ipairs(hs.window.orderedWindows()) do
        local app = w:application()
        local appName = (app and app:name()) or "?"
        if w:isStandard() and w:title() ~= ""
            and appName ~= "Hammerspoon" and not BROWSERS[appName] then
            items[#items + 1] = {
                key = keyForWindow(w),
                app = appName,
                title = w:title(),
                kind = "window",
                selected = obj.autoSelectApps[appName],
            }
        end
    end
    for _, t in ipairs(listBrowserTabs()) do
        items[#items + 1] = {
            key = keyForTabUrl(t.url),
            app = t.app,
            title = t.title,
            kind = "tab",
            selected = obj.autoSelectApps[t.app],
        }
    end
    return items
end

-- Comma-separated, URL-encoded keys -> { ["win:12"] = true, ["tab:https://..."] = true }
local function parseAllowed(str)
    local set = {}
    for part in tostring(str or ""):gmatch("[^,]+") do
        set[urlDecode(part)] = true
    end
    return set
end

local function inputHtml(windowsJson)
    local html = [[
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
    :root {
        color-scheme: dark;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
    }
    html, body {
        width: 100%;
        height: 100%;
        margin: 0;
        overflow: hidden;
        background: transparent;
    }
    body {
        display: grid;
        place-items: center;
    }
    form {
        width: 374px;
        padding: 10px 18px 18px;
        box-sizing: border-box;
        border: 1px solid rgba(255, 255, 255, 0.16);
        border-radius: 16px;
        background: rgba(24, 24, 27, 0.92);
        box-shadow: 0 18px 60px rgba(0, 0, 0, 0.38);
        backdrop-filter: blur(18px);
    }
    .drag-handle {
        height: 18px;
        margin: -2px -4px 8px;
        border-radius: 9px;
        cursor: move;
    }
    .drag-handle::after {
        content: "";
        display: block;
        width: 42px;
        height: 4px;
        margin: 7px auto 0;
        border-radius: 999px;
        background: rgba(255, 255, 255, 0.2);
    }
    label {
        display: block;
        margin: 0 0 8px;
        color: rgba(255, 255, 255, 0.68);
        font-size: 12px;
        font-weight: 600;
    }
    input {
        width: 100%;
        height: 38px;
        margin: 0 0 15px;
        padding: 0 12px;
        box-sizing: border-box;
        border: 1px solid rgba(255, 255, 255, 0.16);
        border-radius: 9px;
        outline: none;
        background: rgba(0, 0, 0, 0.24);
        color: rgba(255, 255, 255, 0.94);
        font-size: 15px;
    }
    input:focus {
        border-color: rgba(78, 179, 255, 0.85);
    }
    .durations {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 8px;
        margin-bottom: 16px;
    }
    .durations input {
        position: absolute;
        opacity: 0;
        pointer-events: none;
    }
    .durations span {
        display: block;
        padding: 10px 0;
        border: 1px solid rgba(255, 255, 255, 0.16);
        border-radius: 9px;
        background: rgba(255, 255, 255, 0.06);
        color: rgba(255, 255, 255, 0.88);
        text-align: center;
        font-size: 14px;
        font-weight: 650;
    }
    .durations input:checked + span {
        border-color: rgba(78, 179, 255, 0.95);
        background: rgba(78, 179, 255, 0.22);
        color: white;
    }
    #filter {
        height: 34px;
        margin-bottom: 8px;
        font-size: 14px;
    }
    .win.hidden {
        display: none;
    }
    .windows {
        max-height: 168px;
        margin-bottom: 16px;
        padding: 4px;
        overflow-y: auto;
        border: 1px solid rgba(255, 255, 255, 0.16);
        border-radius: 9px;
        background: rgba(0, 0, 0, 0.24);
    }
    .windows .empty {
        padding: 14px 8px;
        color: rgba(255, 255, 255, 0.5);
        font-size: 13px;
        text-align: center;
    }
    .win {
        display: flex;
        align-items: center;
        gap: 9px;
        padding: 7px 8px;
        border-radius: 7px;
        cursor: pointer;
    }
    .win:hover {
        background: rgba(255, 255, 255, 0.06);
    }
    .win input {
        width: 15px;
        height: 15px;
        margin: 0;
        flex: 0 0 auto;
        accent-color: rgb(78, 179, 255);
    }
    .win span {
        display: flex;
        flex-direction: column;
        min-width: 0;
        line-height: 1.25;
    }
    .win strong {
        display: flex;
        align-items: center;
        gap: 7px;
        color: rgba(255, 255, 255, 0.92);
        font-size: 13px;
        font-weight: 650;
    }
    .tag {
        flex: 0 0 auto;
        padding: 1px 6px;
        border-radius: 5px;
        font-size: 9px;
        font-style: normal;
        font-weight: 700;
        letter-spacing: 0.4px;
        text-transform: uppercase;
    }
    .tag-window {
        background: rgba(255, 255, 255, 0.14);
        color: rgba(255, 255, 255, 0.7);
    }
    .tag-tab {
        background: rgba(78, 179, 255, 0.22);
        color: rgb(120, 196, 255);
    }
    .win em {
        overflow: hidden;
        color: rgba(255, 255, 255, 0.55);
        font-size: 11px;
        font-style: normal;
        text-overflow: ellipsis;
        white-space: nowrap;
    }
    button {
        width: 100%;
        height: 38px;
        border: 0;
        border-radius: 9px;
        background: rgb(78, 179, 255);
        color: rgb(5, 20, 32);
        font-size: 14px;
        font-weight: 750;
    }
</style>
</head>
<body>
<form id="pomodoro-form">
    <div class="drag-handle" id="drag-handle"></div>
    <label for="title">Title</label>
    <input id="title" name="title" type="text" autocomplete="off" autofocus placeholder="Focus">
    <label>Timer</label>
    <div class="durations">
        <label><input type="radio" name="minutes" value="5"><span>5m</span></label>
        <label><input type="radio" name="minutes" value="15"><span>15m</span></label>
        <label><input type="radio" name="minutes" value="25" checked><span>25m</span></label>
    </div>
    <label>Allowed windows</label>
    <input id="filter" type="text" autocomplete="off" placeholder="Filter by app or title…">
    <div class="windows" id="windows"></div>
    <button type="submit">Start</button>
</form>
<script>
    const form = document.getElementById("pomodoro-form");
    const title = document.getElementById("title");
    const dragHandle = document.getElementById("drag-handle");
    const windowsEl = document.getElementById("windows");
    const filterEl = document.getElementById("filter");
    const ITEMS = __ITEMS_JSON__;
    const rows = [];
    let submitted = false;

    if (ITEMS.length === 0) {
        const empty = document.createElement("div");
        empty.className = "empty";
        empty.textContent = "No open windows or tabs found";
        windowsEl.appendChild(empty);
    } else {
        ITEMS.forEach((item) => {
            const row = document.createElement("label");
            row.className = "win";
            row.dataset.search = (item.app + " " + item.title).toLowerCase();
            const cb = document.createElement("input");
            cb.type = "checkbox";
            cb.className = "win-check";
            cb.value = item.key;
            cb.checked = !!item.selected;
            const span = document.createElement("span");
            const app = document.createElement("strong");
            const tag = document.createElement("i");
            tag.className = "tag tag-" + item.kind;
            tag.textContent = item.kind === "tab" ? "tab" : "win";
            app.appendChild(tag);
            app.appendChild(document.createTextNode(item.app));
            const t = document.createElement("em");
            t.textContent = item.title;
            span.appendChild(app);
            span.appendChild(t);
            row.appendChild(cb);
            row.appendChild(span);
            windowsEl.appendChild(row);
            rows.push(row);
        });

        const noMatch = document.createElement("div");
        noMatch.className = "empty";
        noMatch.textContent = "No matches";
        noMatch.style.display = "none";
        windowsEl.appendChild(noMatch);

        filterEl.addEventListener("input", () => {
            const q = filterEl.value.trim().toLowerCase();
            let visible = 0;
            rows.forEach((row) => {
                const match = q === "" || row.dataset.search.indexOf(q) !== -1;
                row.classList.toggle("hidden", !match);
                if (match) visible++;
            });
            noMatch.style.display = visible === 0 ? "block" : "none";
        });
    }

    function selectedKeys() {
        return Array.from(document.querySelectorAll(".win-check:checked"))
            .map((c) => encodeURIComponent(c.value))
            .join(",");
    }

    function navigate(eventName, params) {
        const query = Object.entries(params || {})
            .map(([key, value]) => encodeURIComponent(key) + "=" + encodeURIComponent(value || ""))
            .join("&");
        location.href = "hammerspoon://" + eventName.toLowerCase() + (query ? "?" + query : "");
    }

    form.addEventListener("submit", (event) => {
        event.preventDefault();
        if (submitted) return;
        submitted = true;
        navigate("pomodorostart", {
            title: title.value,
            minutes: document.querySelector("input[name='minutes']:checked").value,
            allowed: selectedKeys()
        });
    });

    dragHandle.addEventListener("mousedown", (event) => {
        event.preventDefault();
        navigate("pomodorodrag");
    });

    title.focus();
    title.select();

    document.addEventListener("keydown", (event) => {
        if (event.key === "Escape") {
            event.preventDefault();
            navigate("pomodorocancel");
        }
    });
</script>
</body>
</html>
]]
    return (html:gsub("__ITEMS_JSON__", function()
        return windowsJson or "[]"
    end))
end

function obj:_hideInput()
    self:_stopDrag()
    local view = self._webview
    if view then
        self._webview = nil
        -- Defer destruction: _hideInput is called from inside the webview's own
        -- navigation callback (Start/Cancel), and deleting a webview mid-navigation
        -- stalls WebKit. Returning first, then deleting, avoids the UI hang.
        hs.timer.doAfter(0, function() view:delete() end)
    end
end

function obj:_stopDrag()
    if self._dragTap then
        self._dragTap:stop()
        self._dragTap = nil
    end
end

function obj:_startDrag(surface)
    if not surface or self._dragTap then return end

    local origin = surface:topLeft()
    local startMouse = hs.mouse.absolutePosition()
    local dx = startMouse.x - origin.x
    local dy = startMouse.y - origin.y

    self._dragTap = hs.eventtap.new({
        hs.eventtap.event.types.mouseMoved,
        hs.eventtap.event.types.leftMouseDragged,
        hs.eventtap.event.types.leftMouseUp,
    }, function(event)
        if event:getType() == hs.eventtap.event.types.leftMouseUp then
            self:_stopDrag()
            return false
        end

        local p = hs.mouse.absolutePosition()
        surface:topLeft({ x = p.x - dx, y = p.y - dy })
        return false
    end)
    self._dragTap:start()
end

function obj:_stopTimer()
    self:_stopDrag()
    self:_stopFocusGuard()
    if self._timer then
        self._timer:stop()
        self._timer = nil
    end
    if self._canvas then
        self._canvas:delete()
        self._canvas = nil
    end
    self._finishAt = nil
    self._startedAt = nil
    self._durationSec = nil
    self._title = nil
    self._allowedKeys = nil
    self:_clearState()
end

-- Translucent full-screen red overlay nudging the user back to an allowed window.
-- Stays up for as long as focus remains on a disallowed target.
function obj:_showFocus()
    if not self._flashCanvas then
        local f = activeScreen():fullFrame()
        local btnW, btnH = 380, 54
        local btn = { x = (f.w - btnW) / 2, y = f.h / 2 + 60, w = btnW, h = btnH }
        local c = applyOverlay(hs.canvas.new(f))
        -- Don't activate Hammerspoon on click, so the disallowed window stays
        -- frontmost and _currentKey resolves it correctly when the button is hit.
        c:clickActivating(false)
        c:replaceElements({
            {
                type = "rectangle",
                action = "fill",
                fillColor = { red = 0.85, green = 0.1, blue = 0.12, alpha = 0.28 },
            },
            {
                type = "text",
                text = "Focus - Get back to work",
                textColor = { white = 1, alpha = 0.96 },
                textFont = ".AppleSystemUIFontBold",
                textSize = 54,
                textAlignment = "center",
                frame = { x = 0, y = f.h / 2 - 60, w = f.w, h = 120 },
            },
            {
                type = "rectangle",
                id = "allowBtn",
                action = "fill",
                trackMouseDown = true,
                roundedRectRadii = { xRadius = 10, yRadius = 10 },
                fillColor = { white = 1, alpha = 0.16 },
                strokeColor = { white = 1, alpha = 0.5 },
                strokeWidth = 1,
                frame = btn,
            },
            {
                type = "text",
                id = "allowBtnLabel",
                text = "Add this window to my session",
                trackMouseDown = true,
                textColor = { white = 1, alpha = 0.96 },
                textFont = ".AppleSystemUIFontBold",
                textSize = 18,
                textAlignment = "center",
                frame = { x = btn.x, y = btn.y + 15, w = btn.w, h = 26 },
            },
        })
        c:mouseCallback(function(_, event, elementId)
            if event == "mouseDown"
                and (elementId == "allowBtn" or elementId == "allowBtnLabel") then
                self:_allowCurrent()
            end
        end)
        self._flashCanvas = c
    end

    self._flashCanvas:show()
end

-- Add the currently-focused target to the allowed set for the rest of the
-- session, persist it, and drop the overlay.
function obj:_allowCurrent()
    if not self._allowedKeys then return end
    local key = self:_currentKey()
    if not key then return end
    self._allowedKeys[key] = true
    self:_saveState()
    self:_hideFocus()
end

-- Hide the overlay once focus is back on an allowed target.
function obj:_hideFocus()
    if self._flashCanvas then self._flashCanvas:hide() end
end

-- Key of the current focus target: "tab:<url>" for browsers, "win:<id>" otherwise.
function obj:_currentKey()
    local win = hs.window.focusedWindow()
    if not win then return nil end
    local app = win:application()
    local name = app and app:name()
    if name and BROWSERS[name] then
        local url = activeTabUrl(name)
        return url and keyForTabUrl(url) or nil
    end
    return keyForWindow(win)
end

-- Keep the overlay visible while focus is outside the allowed set, and hide it
-- as soon as focus returns to an allowed target. Polled every guard tick;
-- _startFocusGuard already guarantees a non-empty allowed set before starting.
function obj:_checkFocus()
    local key = self:_currentKey()
    if not key then return end
    if self._allowedKeys[key] then
        self:_hideFocus()
        return
    end
    -- Count each guard tick spent on a disallowed target as distraction time,
    -- then persist it (the only field that changes while the timer runs).
    self._distractedSec = self._distractedSec + self.guardIntervalSec
    self:_saveState()
    self:_showFocus()
end

function obj:_startFocusGuard()
    self:_stopFocusGuard()
    if not (self._allowedKeys and next(self._allowedKeys)) then return end

    -- Polling is required: switching browser tabs fires no window-focus event,
    -- and the active tab can only be read via AppleScript.
    self._guardTimer = hs.timer.doEvery(self.guardIntervalSec, function()
        self:_checkFocus()
    end)
end

function obj:_stopFocusGuard()
    if self._guardTimer then
        self._guardTimer:stop()
        self._guardTimer = nil
    end
    if self._flashCanvas then
        self._flashCanvas:delete()
        self._flashCanvas = nil
    end
end

function obj:_renderProgress()
    if not (self._canvas and self._finishAt and self._startedAt and self._durationSec) then return end

    local now = hs.timer.secondsSinceEpoch()
    local remaining = self._finishAt - now
    local elapsed = self._durationSec - remaining
    local progress = math.max(0, math.min(1, elapsed / self._durationSec))
    local w = self.width
    local pad = 14
    local barW = w - pad * 2
    local barH = 8
    local title = self._title or "Focus"

    if #title > 48 then title = title:sub(1, 45) .. "..." end

    self._canvas:replaceElements({
        {
            type = "rectangle",
            id = "bg",
            action = "fill",
            trackMouseDown = true,
            roundedRectRadii = { xRadius = 13, yRadius = 13 },
            fillColor = { red = 0.08, green = 0.08, blue = 0.09, alpha = 0.74 },
            strokeColor = { white = 1, alpha = 0.12 },
            strokeWidth = 0.5,
        },
        {
            type = "text",
            text = title,
            textColor = { white = 1, alpha = 0.94 },
            textFont = ".AppleSystemUIFontBold",
            textSize = 16,
            frame = { x = pad, y = 12, w = w - pad * 2 - 76, h = 23 },
        },
        {
            type = "text",
            text = fmtRemaining(remaining),
            textColor = { white = 1, alpha = 0.82 },
            textFont = "Menlo",
            textSize = 15,
            textAlignment = "right",
            frame = { x = w - pad - 76, y = 13, w = 76, h = 22 },
        },
        {
            type = "rectangle",
            action = "fill",
            roundedRectRadii = { xRadius = barH / 2, yRadius = barH / 2 },
            fillColor = { white = 1, alpha = 0.13 },
            frame = { x = pad, y = 47, w = barW, h = barH },
        },
        {
            type = "rectangle",
            action = "fill",
            roundedRectRadii = { xRadius = barH / 2, yRadius = barH / 2 },
            fillColor = { red = 0.3, green = 0.7, blue = 1, alpha = 0.92 },
            frame = { x = pad, y = 47, w = math.max(barH, math.floor(barW * progress)), h = barH },
        },
        {
            type = "text",
            text = string.format("%d%%", math.floor(progress * 100 + 0.5)),
            textColor = { white = 1, alpha = 0.58 },
            textFont = "Menlo",
            textSize = 12,
            textAlignment = "center",
            frame = { x = pad, y = 65, w = barW, h = 16 },
        },
        {
            type = "text",
            text = "distracted " .. fmtRemaining(self._distractedSec),
            textColor = { red = 1, green = 0.55, blue = 0.55, alpha = 0.75 },
            textFont = "Menlo",
            textSize = 12,
            textAlignment = "left",
            frame = { x = pad, y = 65, w = barW, h = 16 },
        },
    })
end

function obj:_finish()
    local title = self._title or "Pomodoro"
    self:_stopTimer()
    hs.notify.new({ title = "Pomodoro complete", informativeText = title }):send()
    if self.completeSound then
        local sound = hs.sound.getByName(self.completeSound)
        if sound then sound:play() end
    end
end

function obj:startTimer(title, minutes, allowed)
    minutes = tonumber(minutes) or 25
    if minutes ~= 5 and minutes ~= 15 and minutes ~= 25 then minutes = 25 end
    title = trim(title)
    if title == "" then title = "Focus" end

    self:_hideInput()
    self:_stopTimer()

    self._title = title
    self._durationSec = minutes * 60
    self._startedAt = hs.timer.secondsSinceEpoch()
    self._finishAt = self._startedAt + self._durationSec
    self._allowedKeys = parseAllowed(allowed)
    self._distractedSec = 0

    self:_beginTimer()
end

-- Build the banner, focus guard, and tick timer from the currently-set timer
-- fields. Shared by a fresh startTimer and by _restoreState after a reload.
function obj:_beginTimer()
    self._canvas = applyOverlay(hs.canvas.new(frameBelowNotch(self.width, self.height)))
    self._canvas:alpha(0.98)
    self._canvas:show()
    self._canvas:mouseCallback(function(_, event, elementId)
        if event == "mouseDown" and elementId == "bg" then
            self:_startDrag(self._canvas)
        end
    end)

    self:_renderProgress()
    self:_startFocusGuard()
    self:_saveState()
    -- The tick only advances the visible countdown. Persistence is handled at
    -- start (above) and whenever _distractedSec changes (in _checkFocus), so no
    -- per-second settings write is needed here.
    self._timer = hs.timer.doEvery(self.updateIntervalSec, function()
        if hs.timer.secondsSinceEpoch() >= self._finishAt then
            self:_finish()
        else
            self:_renderProgress()
        end
    end)
end

-- Persist the running timer so it can be resumed after a Hammerspoon reload.
-- _finishAt/_startedAt are absolute epoch times, so remaining time is recomputed
-- against the wall clock on restore regardless of how long Hammerspoon was down.
function obj:_saveState()
    if not (self._finishAt and self._startedAt and self._durationSec) then return end
    -- _allowedKeys is a string-keyed set; hs.settings persists it as a plist dict.
    hs.settings.set(SETTINGS_KEY, {
        title = self._title,
        durationSec = self._durationSec,
        startedAt = self._startedAt,
        finishAt = self._finishAt,
        distractedSec = self._distractedSec,
        allowed = self._allowedKeys or {},
    })
end

function obj:_clearState()
    hs.settings.clear(SETTINGS_KEY)
end

-- Resume a persisted timer if one is still running; otherwise discard it.
function obj:_restoreState()
    local s = hs.settings.get(SETTINGS_KEY)
    if not (s and s.finishAt and s.startedAt and s.durationSec) then return end
    if hs.timer.secondsSinceEpoch() >= s.finishAt then
        -- The session already elapsed while Hammerspoon was down.
        self:_clearState()
        return
    end

    self._title = s.title
    self._durationSec = s.durationSec
    self._startedAt = s.startedAt
    self._finishAt = s.finishAt
    self._distractedSec = s.distractedSec or 0
    self._allowedKeys = s.allowed or {}

    self:_beginTimer()
end

function obj:showInput()
    self:_hideInput()

    local view = hs.webview.new(frameBelowNotch(self.inputWidth, self.inputHeight))
        :windowStyle({ "borderless" })
        :allowTextEntry(true)
        :transparent(true)
        :shadow(true)
        :html(inputHtml(hs.json.encode(listItems())))

    view:policyCallback(function(action, _, request)
        if action ~= "navigationAction" then return true end

        local urlValue = request and request.request and request.request.URL
        if not urlValue then return true end
        local url = tostring(urlValue)

        local normalizedUrl = url:lower()

        if normalizedUrl:match("^hammerspoon://pomodorostart") then
            local params = parseQuery(url)
            -- startTimer tears down this webview via _hideInput, which now defers
            -- the delete, so it is safe to call directly from the callback.
            self:startTimer(params.title, params.minutes, params.allowed)
            return false
        end

        if normalizedUrl:match("^hammerspoon://pomodorocancel") then
            self:_hideInput()
            return false
        end

        if normalizedUrl:match("^hammerspoon://pomodorodrag") then
            self:_startDrag(view)
            return false
        end

        return true
    end)

    applyOverlay(view)
    view:show()
    hs.timer.doAfter(0.05, function()
        if self._webview then self._webview:hswindow():focus() end
    end)

    self._webview = view
end

function obj:toggle()
    if self._webview then
        self:_hideInput()
        return
    end

    if self._timer or self._canvas then
        self:_stopTimer()
        return
    end

    self:showInput()
end

function obj:configure(opts)
    opts = opts or {}
    if opts.hotkey then self.hotkey = opts.hotkey end
    if opts.completeSound then self.completeSound = opts.completeSound end
    if opts.updateIntervalSec then self.updateIntervalSec = opts.updateIntervalSec end
    return self
end

function obj:start()
    local startHandler = function(_, params)
        self:startTimer(urlDecode(params.title), params.minutes, params.allowed)
    end
    local cancelHandler = function()
        self:_hideInput()
    end

    hs.urlevent.bind("pomodorostart", startHandler)
    hs.urlevent.bind("pomodoroStart", startHandler)
    hs.urlevent.bind("pomodorocancel", cancelHandler)
    hs.urlevent.bind("pomodoroCancel", cancelHandler)

    if self._hotkey then self._hotkey:delete() end
    self._hotkey = hs.hotkey.bind(self.hotkey[1], self.hotkey[2], function()
        self:toggle()
    end)

    self:_restoreState()
    return self
end

function obj:stop()
    if self._hotkey then self._hotkey:delete(); self._hotkey = nil end
    hs.urlevent.bind("pomodorostart", nil)
    hs.urlevent.bind("pomodoroStart", nil)
    hs.urlevent.bind("pomodorocancel", nil)
    hs.urlevent.bind("pomodoroCancel", nil)
    self:_hideInput()
    self:_stopTimer()
    return self
end

return obj
