--- === WindowKit ===
---
--- Bundled window management: grid, alt-tab letter switcher, absolute layouts,
--- duplicate-window auto-close, and move-to-adjacent-space (PaperWM-backed).

local obj = {}
obj.__index = obj

obj.name = "WindowKit"
obj.version = "1.0"
obj.author = "Abhijeet Rastogi"
obj.license = "MIT"

obj.gridDims = "3x2"
obj.gridMargins = "1x1"
obj.hyperkey = nil
obj.notifyFn = function(_, _, _) end
obj.alertFn  = function(_, _, _) end
obj.autoclose = { rules = {
    { titlePattern = "Google Meet", timeout = 300, count = 2 },
} }
obj.spaces = { paperwmPath = nil }

function obj:configure(opts)
    opts = opts or {}
    if opts.hyperkey then self.hyperkey = opts.hyperkey end
    if opts.notifyFn then self.notifyFn = opts.notifyFn end
    if opts.alertFn  then self.alertFn  = opts.alertFn end
    if opts.gridDims then self.gridDims = opts.gridDims end
    if opts.gridMargins then self.gridMargins = opts.gridMargins end
    if opts.autoclose then self.autoclose = opts.autoclose end
    if opts.spaces then self.spaces = opts.spaces end
    return self
end

function obj:start()
    if not self.hyperkey then error("WindowKit requires .hyperkey") end

    local function load(name) return dofile(hs.spoons.resourcePath(name .. ".lua")) end

    local spaces   = load("spaces")
    self._spaces   = spaces
    local grid     = load("grid")
    local switch   = load("switch")
    local absolute = load("absolute")
    local autoclose = load("autoclose")

    spaces.bind(self)
    grid.bind(self)
    switch.bind(self)
    absolute.bind(self)
    autoclose.start(self)

    self._modules = { spaces = spaces, grid = grid, switch = switch, absolute = absolute, autoclose = autoclose }
    return self
end

function obj:stop()
    if self._modules and self._modules.autoclose then self._modules.autoclose.stop() end
    return self
end

return obj
