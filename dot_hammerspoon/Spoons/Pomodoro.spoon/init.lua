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
obj.inputHeight = 255
obj.updateIntervalSec = 1
obj.completeSound = nil

obj._hotkey = nil
obj._webview = nil
obj._canvas = nil
obj._timer = nil
obj._finishAt = nil
obj._startedAt = nil
obj._durationSec = nil
obj._title = nil
obj._dragTap = nil

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

local function inputHtml()
    return [[
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
    <button type="submit">Start</button>
</form>
<script>
    const form = document.getElementById("pomodoro-form");
    const title = document.getElementById("title");
    const dragHandle = document.getElementById("drag-handle");
    let submitted = false;

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
            minutes: document.querySelector("input[name='minutes']:checked").value
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
end

function obj:_hideInput()
    self:_stopDrag()
    if self._webview then
        self._webview:delete()
        self._webview = nil
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

function obj:startTimer(title, minutes)
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

    self._canvas = hs.canvas.new(frameBelowNotch(self.width, self.height))
    self._canvas:level(hs.canvas.windowLevels.overlay)
    self._canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
        + hs.canvas.windowBehaviors.stationary)
    self._canvas:alpha(0.98)
    self._canvas:show()
    self._canvas:mouseCallback(function(_, event, elementId)
        if event == "mouseDown" and elementId == "bg" then
            self:_startDrag(self._canvas)
        end
    end)

    self:_renderProgress()
    self._timer = hs.timer.doEvery(self.updateIntervalSec, function()
        if hs.timer.secondsSinceEpoch() >= self._finishAt then
            self:_finish()
        else
            self:_renderProgress()
        end
    end)
end

function obj:showInput()
    self:_hideInput()

    local view = hs.webview.new(frameBelowNotch(self.inputWidth, self.inputHeight))
        :windowStyle({ "borderless" })
        :allowTextEntry(true)
        :transparent(true)
        :shadow(true)
        :html(inputHtml())

    view:policyCallback(function(action, _, request)
        if action ~= "navigationAction" then return true end

        local urlValue = request and request.request and request.request.URL
        if not urlValue then return true end
        local url = tostring(urlValue)

        local normalizedUrl = url:lower()

        if normalizedUrl:match("^hammerspoon://pomodorostart") then
            local params = parseQuery(url)
            self:startTimer(params.title, params.minutes)
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

    view:level(hs.canvas.windowLevels.overlay)
    view:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
        + hs.canvas.windowBehaviors.stationary)
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
        self:startTimer(urlDecode(params.title), params.minutes)
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
