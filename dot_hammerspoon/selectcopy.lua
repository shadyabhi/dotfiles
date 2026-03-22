-- Auto-copy selected text to clipboard using macOS Accessibility APIs
-- Uses hs.uielement and hs.eventtap to detect text selection changes

local logger = hs.logger.new('selectcopy', 'info')

local prevSelection = ""
local copyTimer = nil

-- Get the currently selected text from the focused UI element
local function getSelectedText()
    local elem = hs.axuielement.systemWideElement()
    local focused = elem:attributeValue("AXFocusedUIElement")
    if not focused then return nil end

    local selectedText = focused:attributeValue("AXSelectedText")
    return selectedText
end

-- Copy selected text to pasteboard if it changed
local function copyIfChanged()
    local text = getSelectedText()
    if text and text ~= "" and text ~= prevSelection then
        prevSelection = text
        hs.pasteboard.setContents(text)
        logger.i("Auto-copied selection: " .. string.sub(text, 1, 50))
    end
end

-- Watch for mouse up events (end of drag-select)
local mouseWatcher = hs.eventtap.new({hs.eventtap.event.types.leftMouseUp}, function(event)
    -- Small delay to let the selection register
    if copyTimer then copyTimer:stop() end
    copyTimer = hs.timer.doAfter(0.1, copyIfChanged)
    return false
end)

mouseWatcher:start()
logger.i("selectcopy: auto-copy on selection enabled")
