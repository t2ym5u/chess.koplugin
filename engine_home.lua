-- ---------------------------------------------------------------------------
-- engine_home.lua — the built-in alpha-beta AI, exposed via the same
-- interface engine_uci.lua implements, so screen.lua can dispatch to either
-- without caring which one is active.
--
-- Engine interface: isAvailable(), requestMove(board, difficulty, callback),
-- stop(), onNewGame(). requestMove is asynchronous (callback receives the
-- move, or nil if none) even though this backend resolves instantly, so the
-- "AI is thinking" pause on-screen behaves the same for both backends.
-- ---------------------------------------------------------------------------

local UIManager = require("ui/uimanager")

local EngineHome = {}
EngineHome.__index = EngineHome

function EngineHome:new()
    return setmetatable({}, self)
end

function EngineHome:isAvailable()
    return true
end

function EngineHome:requestMove(board, difficulty, callback)
    local depth = (difficulty == "easy") and 1 or (difficulty == "hard") and 3 or 2
    local token = {}
    self._active_token = token
    UIManager:scheduleIn(0.1, function()
        if self._active_token ~= token then return end  -- cancelled (e.g. undo pressed)
        callback(board:getAIMove(depth))
    end)
end

-- Cancels an in-flight requestMove (e.g. the user hit undo while "thinking").
function EngineHome:cancelPending()
    self._active_token = nil
end

function EngineHome:stop()
    self._active_token = nil
end

function EngineHome:onNewGame()
end

return EngineHome
