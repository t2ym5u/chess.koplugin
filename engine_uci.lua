-- ---------------------------------------------------------------------------
-- engine_uci.lua — optional Stockfish/UCI backend, mirroring engine_home.lua's
-- interface: isAvailable(), requestMove(board, difficulty, callback), stop(),
-- onNewGame(), cancelPending().
--
-- Only usable where fork()/execvp()/pipe() work (uci_process.lua) and a
-- binary is present at PLUGIN_DIR/bin/stockfish. Never assumed available by
-- default — the screen only offers it once EngineUCI.binaryAvailable() is
-- true, and every failure (spawn, handshake timeout) degrades to "not ready"
-- rather than raising, so the home engine remains the safe fallback.
-- ---------------------------------------------------------------------------

local UIManager = require("ui/uimanager")

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end
local UciProcess = lrequire("uci_process")
local PGN        = lrequire("pgn")

local HANDSHAKE_TIMEOUT_SEC = 3
local POLL_INTERVAL         = 0.1

local PROMO_LETTER_FROM_PTYPE = { [2] = "r", [3] = "n", [4] = "b", [5] = "q" }
local PTYPE_FROM_PROMO_LETTER = { q = 5, r = 2, b = 4, n = 3 }

local EngineUCI = {}
EngineUCI.__index = EngineUCI

function EngineUCI:new(binary_path)
    local o = setmetatable({}, self)
    o.binary_path = binary_path
    o.state = "unstarted"  -- unstarted | starting | ready | failed
    o.options = {}
    o.pending_callback = nil
    o._reader_running = false
    return o
end

-- Cheap static check (no spawn): does the binary exist and look executable?
function EngineUCI.binaryAvailable(binary_path)
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then return false end
    local mode = lfs.attributes(binary_path, "mode")
    if mode ~= "file" then return false end
    local perm = lfs.attributes(binary_path, "permissions")
    return type(perm) == "string" and perm:find("x") ~= nil
end

function EngineUCI:isAvailable()
    return self.state == "ready"
end

function EngineUCI:_send(line)
    if self.write_fd then UciProcess.writeLine(self.write_fd, line) end
end

function EngineUCI:_startPolling()
    if self._reader_running then return end
    self._reader_running = true
    local function poll()
        if not self.read_fd then self._reader_running = false; return end
        UciProcess.pollLines(self.read_fd, function(line) self:_onLine(line) end)
        UIManager:scheduleIn(POLL_INTERVAL, poll)
    end
    UIManager:scheduleIn(POLL_INTERVAL, poll)
end

function EngineUCI:_onLine(line)
    line = line:match("^%s*(.-)%s*$")
    if line:find("^option") then
        local name = line:match("name%s+(.-)%s+type")
        if name then self.options[name] = true end
    elseif line == "uciok" then
        if self.state == "starting" then
            self.state = "ready"
            -- No .nnue network file is bundled, so classical eval only.
            self:_send("setoption name Use NNUE value false")
            local cb = self._on_ready
            self._on_ready = nil
            if cb then cb(true) end
        end
    elseif line:find("^bestmove") then
        local mv = line:match("^bestmove%s+(%S+)")
        local cb = self.pending_callback
        self.pending_callback = nil
        if cb then cb(mv) end
    end
end

-- Spawns + handshakes the engine. Calls on_ready(ok) exactly once, whether
-- that's success, spawn failure, or handshake timeout. A call while already
-- starting/ready just chains onto (or immediately satisfies) on_ready.
function EngineUCI:start(on_ready)
    if self.state == "ready" then
        if on_ready then on_ready(true) end
        return
    end
    if self.state == "starting" then
        local prev = self._on_ready
        self._on_ready = function(ok)
            if prev then prev(ok) end
            if on_ready then on_ready(ok) end
        end
        return
    end

    local pid, rfd, wfd = UciProcess.spawn(self.binary_path, { self.binary_path })
    if not pid then
        self.state = "failed"
        if on_ready then on_ready(false) end
        return
    end

    self.pid, self.read_fd, self.write_fd = pid, rfd, wfd
    self.state = "starting"
    self._on_ready = on_ready
    self:_startPolling()
    self:_send("uci")

    local deadline = os.time() + HANDSHAKE_TIMEOUT_SEC
    local function checkTimeout()
        if self.state ~= "starting" then return end
        if os.time() >= deadline then
            local cb = self._on_ready
            self._on_ready = nil
            self:stop()          -- closes fds; also resets state to "unstarted"
            self.state = "failed" -- ...then mark it distinctly failed (not just "never tried")
            if cb then cb(false) end
            return
        end
        UIManager:scheduleIn(POLL_INTERVAL, checkTimeout)
    end
    UIManager:scheduleIn(POLL_INTERVAL, checkTimeout)
end

function EngineUCI:stop()
    if self.write_fd then pcall(function() UciProcess.writeLine(self.write_fd, "quit") end) end
    UciProcess.closeFd(self.read_fd)
    UciProcess.closeFd(self.write_fd)
    self.pid, self.read_fd, self.write_fd = nil, nil, nil
    self.state = "unstarted"
    self.pending_callback = nil
end

-- Cancels an in-flight requestMove (e.g. the user hit undo while the engine
-- was thinking) without killing the process itself.
function EngineUCI:cancelPending()
    if self.pending_callback then
        self:_send("stop")
        self.pending_callback = nil
    end
end

function EngineUCI:onNewGame()
    if self.state == "ready" then self:_send("ucinewgame") end
end

function EngineUCI:_moveToUCI(move)
    local from = PGN.squareName(move.fr, move.fc)
    local to   = PGN.squareName(move.tr, move.tc)
    local promo = ""
    if move.special == "promo" then
        local pt = ((move.promo_piece - 1) % 6) + 1
        promo = PROMO_LETTER_FROM_PTYPE[pt] or "q"
    end
    return from .. to .. promo
end

function EngineUCI:_uciToMove(board, uci_move)
    if not uci_move or uci_move == "(none)" or #uci_move < 4 then return nil end
    local fr, fc = PGN.parseSquare(uci_move:sub(1, 2))
    local tr, tc = PGN.parseSquare(uci_move:sub(3, 4))
    if not fr or not tr then return nil end
    local promo_pt = #uci_move == 5 and PTYPE_FROM_PROMO_LETTER[uci_move:sub(5, 5)] or nil

    for _, m in ipairs(board:getLegalMoves()) do
        if m.fr == fr and m.fc == fc and m.tr == tr and m.tc == tc then
            if m.special == "promo" then
                if promo_pt and (((m.promo_piece - 1) % 6) + 1) == promo_pt then return m end
            else
                return m
            end
        end
    end
    return nil
end

-- difficulty: "easy" | "medium" | "hard". Uses UCI_Elo if the engine
-- advertises it (most modern Stockfish builds do), else a fixed movetime.
function EngineUCI:requestMove(board, difficulty, callback)
    if self.state ~= "ready" then callback(nil); return end

    if self.options["UCI_Elo"] then
        local elo = ({ easy = 1200, medium = 1600, hard = 2000 })[difficulty] or 1600
        self:_send("setoption name UCI_LimitStrength value true")
        self:_send(("setoption name UCI_Elo value %d"):format(elo))
    end

    local uci_moves = {}
    for _, entry in ipairs(board._move_history) do
        uci_moves[#uci_moves + 1] = self:_moveToUCI(entry.move)
    end
    local position = "position startpos"
    if #uci_moves > 0 then position = position .. " moves " .. table.concat(uci_moves, " ") end
    self:_send(position)

    self.pending_callback = function(uci_move)
        callback(self:_uciToMove(board, uci_move))
    end
    local movetime = ({ easy = 500, medium = 1500, hard = 4000 })[difficulty] or 1500
    self:_send(("go movetime %d"):format(movetime))
end

return EngineUCI
