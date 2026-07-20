local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = _dir .. "?.lua;" .. _dir .. "common/?.lua;" .. package.path

local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local PluginBase   = require("plugin_base")
local _            = require("i18n")

require("i18n").extend(lrequire("i18n_fr"))
local EchecsScreen = lrequire("screen")

-- ---------------------------------------------------------------------------
-- EchecsPlugin
-- ---------------------------------------------------------------------------

local EchecsPlugin = PluginBase:extend{
    name      = "echecs",
    menu_text = _("Échecs"),
    menu_hint = "tools",
}

function EchecsPlugin:createScreen()
    return EchecsScreen:new{ plugin = self }
end

return EchecsPlugin
