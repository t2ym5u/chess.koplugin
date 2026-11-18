-- Flip only redraws the board.
-- UIManager repaints top-level widgets only, so these handlers must mark
-- the screen dirty: marking the board itself dirty refreshes the old
-- pixels and the action looks ignored.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

describe("board refresh", function()
    local saved = {}
    local dirty   -- widgets passed to UIManager:setDirty

    -- Every other module is a stub: any field is another stub, and calling
    -- one returns its last argument, so Class:extend{} returns its table
    -- and _("x") returns "x".
    local function stub()
        return setmetatable({}, {
            __index = function(t, k) local s = stub(); rawset(t, k, s); return s end,
            __call  = function(_, a, b) if b ~= nil then return b end return a end,
        })
    end

    local function stubSearcher(name)
        return function() return stub() end, name
    end

    setup(function()
        -- The real grid_widget_base (common/ is game-common): its refresh is
        -- the one under test.
        saved.path = package.path
        package.path = DIR .. "common/?.lua;" .. package.path
        package.loaded["grid_widget_base"] = nil
        saved.loaded = {}
        for k, v in pairs(package.loaded) do saved.loaded[k] = v end
        for k in pairs(saved.loaded) do
            if type(k) == "string" and k:sub(1, #DIR) == DIR then package.loaded[k] = nil end
        end
        local stubs = { "device", "screen_base", "menu_helper", "i18n" }
        for _, name in ipairs(stubs) do package.loaded[name] = stub() end
        -- GridWidgetBase extends InputContainer, and the board extends it.
        package.loaded["ui/widget/container/inputcontainer"] = {
            extend = function(base, t) return setmetatable(t or {}, { __index = base }) end,
        }
        package.loaded["ui/uimanager"] = setmetatable({
            setDirty = function(_, w) dirty[#dirty + 1] = w end,
        }, { __index = function() return function() end end })
        local searchers = package.searchers or package.loaders
        searchers[#searchers + 1] = stubSearcher
    end)

    teardown(function()
        local searchers = package.searchers or package.loaders
        for i = #searchers, 1, -1 do
            if searchers[i] == stubSearcher then table.remove(searchers, i) end
        end
        for k in pairs(package.loaded) do
            if saved.loaded[k] == nil then package.loaded[k] = nil end
        end
        for k, v in pairs(saved.loaded) do package.loaded[k] = v end
        package.path = saved.path
    end)

    -- A screen built from `fields`; methods it does not define do nothing.
    local function fakeScreen(Screen, fields)
        return setmetatable(fields, { __index = function(_, k)
            return Screen[k] or function() end
        end })
    end

    local function noop() end

    -- The widget, painted at the top left; `fields` are added to it.
    local function fakeWidget(Class, fields)
        local w = fields or {}
        w.paint_rect, w.dimen = { x = 0, y = 0, w = 100, h = 100 }, {}
        return setmetatable(w, { __index = Class })
    end

    it("marks the screen dirty when the board is flipped", function()
        local Screen = dofile(DIR .. "screen.lua")
        local Widget = package.loaded[DIR .. "board_widget"]
        local scr = fakeScreen(Screen, { board_widget = fakeWidget(Widget) })
        local function check(label, fn)
            dirty = {}
            fn()
            local found = false
            for _, d in ipairs(dirty) do if d == scr then found = true end end
            assert.is_true(found, label .. " must mark the screen dirty")
        end
        check("onFlipBoard", function() scr:onFlipBoard() end)
    end)
end)
