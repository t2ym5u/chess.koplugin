-- ---------------------------------------------------------------------------
-- chess_clock.lua — per-side chess clock (base time + increment)
--
-- Deliberately knows nothing about ChessBoard: the screen is responsible for
-- calling switchPlayer() after each move and stop()/start() around undo/redo
-- and game-end. Ticking uses UIManager:scheduleIn (no FFI/subprocess needed).
-- ---------------------------------------------------------------------------

local UIManager = require("ui/uimanager")

local ChessClock = {}
ChessClock.__index = ChessClock

local TICK_SECONDS = 1

-- opts: { base_minutes = {w=,b=}, increment_seconds = {w=,b=},
--         on_tick = function(), on_timeout = function(color) }
function ChessClock:new(opts)
    opts = opts or {}
    local o = setmetatable({}, self)
    local base_minutes     = opts.base_minutes or { w = 10, b = 10 }
    local increment_seconds = opts.increment_seconds or { w = 0, b = 0 }
    o.base      = { w = base_minutes.w * 60, b = base_minutes.b * 60 }
    o.increment = { w = increment_seconds.w, b = increment_seconds.b }
    o.remaining = { w = o.base.w, b = o.base.b }
    o.turn        = "w"
    o.running     = false
    o.on_tick     = opts.on_tick
    o.on_timeout  = opts.on_timeout
    o._start_time = nil
    o._gen        = 0  -- bumped on stop()/reset() to invalidate stale scheduled ticks
    return o
end

function ChessClock:_tick(gen)
    if not self.running or gen ~= self._gen then return end
    local elapsed   = os.difftime(os.time(), self._start_time)
    local remaining = self.remaining[self.turn] - elapsed
    if remaining <= 0 then
        self.remaining[self.turn] = 0
        self.running = false
        if self.on_tick then self.on_tick() end
        if self.on_timeout then self.on_timeout(self.turn) end
        return
    end
    if self.on_tick then self.on_tick() end
    UIManager:scheduleIn(TICK_SECONDS, function() self:_tick(gen) end)
end

function ChessClock:start()
    if self.running then return end
    self.running    = true
    self._start_time = os.time()
    self._gen = self._gen + 1
    UIManager:scheduleIn(TICK_SECONDS, function() self:_tick(self._gen) end)
end

function ChessClock:stop()
    if not self.running then return end
    local elapsed = os.difftime(os.time(), self._start_time)
    self.remaining[self.turn] = math.max(0, self.remaining[self.turn] - elapsed)
    self.running = false
    self._gen = self._gen + 1
end

-- Call once the side that just moved (self.turn) has finished its move:
-- credits its increment, then hands the running clock to the other side.
function ChessClock:switchPlayer()
    local mover = self.turn
    self:stop()
    self.remaining[mover] = self.remaining[mover] + self.increment[mover]
    self.turn = (mover == "w") and "b" or "w"
    self:start()
end

-- Re-syncs the ticking side to `turn` without touching remaining time —
-- used after undo/redo, where time already spent is not refunded.
function ChessClock:syncTurn(turn)
    self:stop()
    self.turn = turn
    self:start()
end

function ChessClock:reset()
    self.running = false
    self._gen = self._gen + 1
    self.turn = "w"
    self.remaining = { w = self.base.w, b = self.base.b }
end

function ChessClock:configure(base_minutes, increment_seconds)
    self.base      = { w = base_minutes.w * 60, b = base_minutes.b * 60 }
    self.increment = { w = increment_seconds.w, b = increment_seconds.b }
    self:reset()
end

function ChessClock:getRemainingTime(color)
    if self.running and color == self.turn then
        local elapsed = os.difftime(os.time(), self._start_time)
        return math.max(0, self.remaining[color] - elapsed)
    end
    return self.remaining[color]
end

function ChessClock:formatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h = math.floor(seconds / 3600)
    local m = math.floor(seconds / 60) % 60
    local s = seconds % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%02d:%02d", m, s)
end

function ChessClock:serialize()
    return {
        base      = { w = self.base.w, b = self.base.b },
        increment = { w = self.increment.w, b = self.increment.b },
        remaining = { w = self:getRemainingTime("w"), b = self:getRemainingTime("b") },
        turn      = self.turn,
    }
end

function ChessClock:load(data)
    if type(data) ~= "table" then return false end
    self.base      = data.base or self.base
    self.increment = data.increment or self.increment
    self.remaining = data.remaining or { w = self.base.w, b = self.base.b }
    self.turn      = data.turn or "w"
    self.running   = false
    self._start_time = nil
    self._gen = self._gen + 1
    return true
end

return ChessClock
