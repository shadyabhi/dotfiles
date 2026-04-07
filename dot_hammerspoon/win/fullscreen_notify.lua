--[[
    When a window matching a rule enters fullscreen, show a Mac notification.
    If that notification is still visible (not dismissed or acted on) after
    unattendedSeconds — default 300 when omitted — send the same alert to your
    phone via Pushover.

    Pushover credentials (used when the Mac banner is left unattended):
      hs.settings.set("pushover", { token = "APP_TOKEN", user = "USER_KEY" })

    Rules use the same shape as below; unattendedSeconds is optional and
    defaults to 300 so you can add new keys without breaking older entries.
]]

local logger = hs.logger.new("fullscreen_notify", "info")

local PUSHOVER_URL = "https://api.pushover.net/1/messages.json"
local DEFAULT_UNATTENDED_SECONDS = 300

-- titlePattern: plain substring match on window title (same idea as win/auto_close.lua)
local rules = {
    -- { titlePattern = "Google Meet" },
}

local function getPushoverSettings()
    return hs.settings.get("pushover")
end

local function unattendedSeconds(rule)
    local s = rule.unattendedSeconds
    if s == nil then
        return DEFAULT_UNATTENDED_SECONDS
    end
    local n = tonumber(s)
    if not n or n < 0 then
        return DEFAULT_UNATTENDED_SECONDS
    end
    return n
end

local function matchesRule(win, rule)
    local title = win:title() or ""
    return title:find(rule.titlePattern, 1, true) ~= nil
end

local function findMatchingRule(win)
    for _, rule in ipairs(rules) do
        if matchesRule(win, rule) then
            return rule
        end
    end
    return nil
end

local function notificationStillDelivered(n)
    local ok, result = pcall(function()
        return hs.fnutils.contains(hs.notify.deliveredNotifications(), n)
    end)
    return ok and result
end

local function sendPushover(poTitle, poMessage)
    local cfg = getPushoverSettings()
    if type(cfg) ~= "table" then
        logger.w("Pushover skipped: hs.settings key \"pushover\" is not a table")
        return
    end
    local token = cfg.token
    local user = cfg.user
    if type(token) ~= "string" or token == "" or type(user) ~= "string" or user == "" then
        logger.w("Pushover skipped: set hs.settings \"pushover\".token and .user")
        return
    end
    local body = table.concat({
        "token=" .. hs.http.encodeForQuery(token),
        "&user=" .. hs.http.encodeForQuery(user),
        "&title=" .. hs.http.encodeForQuery(poTitle),
        "&message=" .. hs.http.encodeForQuery(poMessage),
    })
    hs.http.asyncPost(PUSHOVER_URL, body, {
        ["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8",
    }, function(code, resp, _)
        if type(code) == "number" and code >= 200 and code < 300 then
            logger.i("Pushover sent")
        else
            logger.e("Pushover failed: " .. tostring(code) .. " " .. tostring(resp))
        end
    end)
end

if #rules > 0 then
    local wf = hs.window.filter.new(true)
    wf:subscribe(hs.window.filter.windowFullscreened, function(win)
        local rule = findMatchingRule(win)
        if not rule then
            return
        end

        local appTitle = win:application() and win:application():title() or "?"
        local winTitle = win:title() or ""
        local delay = unattendedSeconds(rule)

        local n = hs.notify.new(nil, {
            title = "Fullscreen",
            informativeText = appTitle .. " — " .. winTitle .. " (dismiss to acknowledge)",
            withdrawAfter = 0,
            alwaysPresent = true,
        })
        n:send()

        hs.timer.doAfter(delay, function()
            if not notificationStillDelivered(n) then
                logger.i("Fullscreen banner cleared; not sending Pushover")
                return
            end
            sendPushover(
                "Fullscreen unattended",
                appTitle .. ": " .. winTitle .. " — Mac notification still up after " .. tostring(delay) .. "s"
            )
            pcall(function()
                n:withdraw()
            end)
        end)
    end)
    logger.i("Fullscreen notify + Pushover: " .. #rules .. " rule(s)")
else
    logger.i("Fullscreen notify: no rules; add titlePattern entries to win/fullscreen_notify.lua")
end
