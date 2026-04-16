local hotkey = require "hs.hotkey"
local window = require "hs.window"
local spaces = require "hs.spaces"
local notify = require("notify")
local MC = dofile(hs.configdir .. "/Spoons/PaperWM.spoon/mission_control.lua")

function flashScreen(screen)
   local flash=hs.canvas.new(screen:fullFrame()):appendElements({
	 action = "fill",
	 fillColor = { alpha = 0.35, red=1},
	 type = "rectangle"})
   flash:show()
   hs.timer.doAfter(.25, function () flash:delete() end)
end

function getGoodFocusedWindow(nofull)
   local win = window.focusedWindow()
   if not win or not win:isStandard() then return end
   if nofull and win:isFullScreen() then return end
   return win
end

function moveWindowOneSpace(dir, switch)
   local win = getGoodFocusedWindow(true)
   if not win then return end

   local screen = win:screen()
   local uuid = screen:getUUID()
   local screenSpaces = spaces.allSpaces()[uuid]
   if not screenSpaces then return end

   -- Filter to user spaces only
   local userSpaces = {}
   for _, spc in ipairs(screenSpaces) do
      if spaces.spaceType(spc) == "user" then
         userSpaces[#userSpaces + 1] = spc
      end
   end

   if #userSpaces <= 1 then
      notify.alert("Spaces", "Only one space available")
      return
   end

   local currentSpace = spaces.windowSpaces(win)
   if not currentSpace then return end
   currentSpace = currentSpace[1]

   -- Find current position in user spaces
   local currentIdx
   for i, spc in ipairs(userSpaces) do
      if spc == currentSpace then
         currentIdx = i
         break
      end
   end
   if not currentIdx then return end

   local targetIdx = dir == "right" and currentIdx + 1 or currentIdx - 1
   if targetIdx < 1 or targetIdx > #userSpaces then
      flashScreen(screen)
      return
   end

   local targetSpace = userSpaces[targetIdx]
   local ok, err = MC:moveWindowToSpace(win, targetSpace)
   if not ok then
      notify.alert("Spaces", err)
   end
end

h_bind("[", function() moveWindowOneSpace("left",true) end)
h_bind("]", function() moveWindowOneSpace("right",true) end)
