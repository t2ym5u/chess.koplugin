-- Startup cost: KOReader loads every plugin's main.lua when it starts, and
-- keeps what it loaded for the whole session, whether the game is played or
-- not. main.lua must therefore not pull in the game screen -- nor the board,
-- word lists or puzzle banks behind it: those load on the first
-- createScreen(). Only the translations (i18n_fr.lua) load at startup.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

describe("main.lua at KOReader startup", function()
    local saved = {}

    -- Any module main.lua requires is a permissive stub: PluginBase:extend{}
    -- returns the class table, _("x") returns "x", everything else is a
    -- function returning its argument.
    local function stub()
        return setmetatable({}, {
            __index = function() return function(_, o) return o or {} end end,
            __call  = function(_, s) return s end,
        })
    end

    local function stubSearcher(name)
        return function() return stub() end, name
    end

    setup(function()
        saved.path = package.path
        saved.preload = {}
        for _, name in ipairs({ "plugin_base", "i18n" }) do
            saved.preload[name] = package.preload[name]
            package.preload[name] = stub
        end
        saved.loaded = {}
        for k, v in pairs(package.loaded) do saved.loaded[k] = v end
        for k in pairs(saved.loaded) do
            if type(k) == "string" and k:sub(1, #DIR) == DIR then package.loaded[k] = nil end
        end
        package.loaded.plugin_base, package.loaded.i18n = nil, nil
        local searchers = package.searchers or package.loaders
        searchers[#searchers + 1] = stubSearcher
    end)

    teardown(function()
        local searchers = package.searchers or package.loaders
        for i = #searchers, 1, -1 do
            if searchers[i] == stubSearcher then table.remove(searchers, i) end
        end
        for name, v in pairs(saved.preload) do package.preload[name] = v end
        for k in pairs(package.loaded) do
            if saved.loaded[k] == nil then package.loaded[k] = nil end
        end
        for k, v in pairs(saved.loaded) do package.loaded[k] = v end
        package.path = saved.path
    end)

    it("loads none of the game's own modules but its translations", function()
        local Plugin = dofile(DIR .. "main.lua")
        assert.is_table(Plugin)
        assert.is_function(Plugin.createScreen)
        local loaded = {}
        for k in pairs(package.loaded) do
            if type(k) == "string" and k:sub(1, #DIR) == DIR then
                loaded[#loaded + 1] = k:sub(#DIR + 1)
            end
        end
        table.sort(loaded)
        local allowed = { i18n_fr = true }
        for _, name in ipairs(loaded) do
            assert.is_true(allowed[name] ~= nil, name .. " was loaded with main.lua")
        end
    end)
end)
