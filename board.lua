-- ---------------------------------------------------------------------------
-- ChessBoard — complete chess engine for chess.koplugin
--
-- Coordinate system:
--   r=1  → top of screen → black's back rank (rank 8 in chess notation)
--   r=8  → bottom of screen → white's back rank (rank 1)
--   c=1  → a-file, c=8 → h-file
--
-- Piece encoding:
--   0  = empty
--   1  = white pawn,   2  = white rook,   3  = white knight
--   4  = white bishop, 5  = white queen,  6  = white king
--   7  = black pawn,   8  = black rook,   9  = black knight
--   10 = black bishop, 11 = black queen,  12 = black king
-- ---------------------------------------------------------------------------

-- Load pgn.lua by absolute path (not a plain require by name) so this never
-- collides with another plugin's same-named module in package.loaded.
local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end
local PGN = lrequire("pgn")

local ChessBoard = {}
ChessBoard.__index = ChessBoard

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

ChessBoard.EMPTY    = 0
ChessBoard.W_PAWN   = 1
ChessBoard.W_ROOK   = 2
ChessBoard.W_KNIGHT = 3
ChessBoard.W_BISHOP = 4
ChessBoard.W_QUEEN  = 5
ChessBoard.W_KING   = 6
ChessBoard.B_PAWN   = 7
ChessBoard.B_ROOK   = 8
ChessBoard.B_KNIGHT = 9
ChessBoard.B_BISHOP = 10
ChessBoard.B_QUEEN  = 11
ChessBoard.B_KING   = 12

-- Material values indexed by piece (white positive, black negative).
-- [0] is the empty square: before 1.3.0 the table started at index 1 with
-- that 0, so every value was shifted one piece along (white pawns worth
-- nothing, black pawns worth +20000 to white) and the AI played nonsense.
local MAT = { [0] = 0, 100, 500, 320, 330, 900, 20000, -100, -500, -320, -330, -900, -20000 }

-- Piece-square bonus tables (indexed 1..8 for rows, white's perspective)
-- For white pieces the row index is (9-r) so r=8 (white's rank 1) maps to index 1
-- For pawns: encourage advancement
local PST_PAWN = {
    { 0,  0,  0,  0,  0,  0,  0,  0},
    {50, 50, 50, 50, 50, 50, 50, 50},
    {10, 10, 20, 30, 30, 20, 10, 10},
    { 5,  5, 10, 25, 25, 10,  5,  5},
    { 0,  0,  0, 20, 20,  0,  0,  0},
    { 5, -5,-10,  0,  0,-10, -5,  5},
    { 5, 10, 10,-20,-20, 10, 10,  5},
    { 0,  0,  0,  0,  0,  0,  0,  0},
}
-- Knights prefer center
local PST_KNIGHT = {
    {-50,-40,-30,-30,-30,-30,-40,-50},
    {-40,-20,  0,  0,  0,  0,-20,-40},
    {-30,  0, 10, 15, 15, 10,  0,-30},
    {-30,  5, 15, 20, 20, 15,  5,-30},
    {-30,  0, 15, 20, 20, 15,  0,-30},
    {-30,  5, 10, 15, 15, 10,  5,-30},
    {-40,-20,  0,  5,  5,  0,-20,-40},
    {-50,-40,-30,-30,-30,-30,-40,-50},
}
-- Bishops prefer diagonals
local PST_BISHOP = {
    {-20,-10,-10,-10,-10,-10,-10,-20},
    {-10,  0,  0,  0,  0,  0,  0,-10},
    {-10,  0,  5, 10, 10,  5,  0,-10},
    {-10,  5,  5, 10, 10,  5,  5,-10},
    {-10,  0, 10, 10, 10, 10,  0,-10},
    {-10, 10, 10, 10, 10, 10, 10,-10},
    {-10,  5,  0,  0,  0,  0,  5,-10},
    {-20,-10,-10,-10,-10,-10,-10,-20},
}
-- Rooks prefer open files and 7th rank
local PST_ROOK = {
    { 0,  0,  0,  0,  0,  0,  0,  0},
    { 5, 10, 10, 10, 10, 10, 10,  5},
    {-5,  0,  0,  0,  0,  0,  0, -5},
    {-5,  0,  0,  0,  0,  0,  0, -5},
    {-5,  0,  0,  0,  0,  0,  0, -5},
    {-5,  0,  0,  0,  0,  0,  0, -5},
    {-5,  0,  0,  0,  0,  0,  0, -5},
    { 0,  0,  0,  5,  5,  0,  0,  0},
}
-- King safety: stay in corner in middlegame
local PST_KING_MG = {
    {-30,-40,-40,-50,-50,-40,-40,-30},
    {-30,-40,-40,-50,-50,-40,-40,-30},
    {-30,-40,-40,-50,-50,-40,-40,-30},
    {-30,-40,-40,-50,-50,-40,-40,-30},
    {-20,-30,-30,-40,-40,-30,-30,-20},
    {-10,-20,-20,-20,-20,-20,-20,-10},
    { 20, 20,  0,  0,  0,  0, 20, 20},
    { 20, 30, 10,  0,  0, 10, 30, 20},
}
-- Queen: active but not too early
local PST_QUEEN = {
    {-20,-10,-10, -5, -5,-10,-10,-20},
    {-10,  0,  0,  0,  0,  0,  0,-10},
    {-10,  0,  5,  5,  5,  5,  0,-10},
    { -5,  0,  5,  5,  5,  5,  0, -5},
    {  0,  0,  5,  5,  5,  5,  0, -5},
    {-10,  5,  5,  5,  5,  5,  0,-10},
    {-10,  0,  5,  0,  0,  0,  0,-10},
    {-20,-10,-10, -5, -5,-10,-10,-20},
}
-- King endgame: centralize
local PST_KING_EG = {
    {-50,-40,-30,-20,-20,-30,-40,-50},
    {-30,-20,-10,  0,  0,-10,-20,-30},
    {-30,-10, 20, 30, 30, 20,-10,-30},
    {-30,-10, 30, 40, 40, 30,-10,-30},
    {-30,-10, 30, 40, 40, 30,-10,-30},
    {-30,-10, 20, 30, 30, 20,-10,-30},
    {-30,-30,  0,  0,  0,  0,-30,-30},
    {-50,-30,-30,-30,-30,-30,-30,-50},
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function isWhite(v) return v >= 1 and v <= 6 end
local function isBlack(v) return v >= 7 and v <= 12 end
local function pieceColor(v)
    if v >= 1 and v <= 6  then return "w" end
    if v >= 7 and v <= 12 then return "b" end
    return nil
end
local function sameColor(a, b)
    return (a >= 1 and a <= 6 and b >= 1 and b <= 6)
        or (a >= 7 and a <= 12 and b >= 7 and b <= 12)
end
-- Returns 1..6 for both colors (pawn=1,rook=2,knight=3,bishop=4,queen=5,king=6)
local function pieceType(v)
    if v == 0 then return 0 end
    return ((v - 1) % 6) + 1
end
local function inBoard(r, c) return r >= 1 and r <= 8 and c >= 1 and c <= 8 end

-- Direction tables shared by move generation and attack detection (hoisted
-- so the AI's millions of calls don't allocate them afresh every time).
local KN_DR = {-2,-2,-1,-1,1,1,2,2}
local KN_DC = {-1,1,-2,2,-2,2,-1,1}
local DIRS_ORTH = {{-1,0},{1,0},{0,-1},{0,1}}
local DIRS_DIAG = {{-1,-1},{-1,1},{1,-1},{1,1}}
local DIRS_ALL  = {{-1,-1},{-1,1},{1,-1},{1,1},{-1,0},{1,0},{0,-1},{0,1}}
local PAWN_DCS  = {-1, 1}
local PROMO_W   = {5, 2, 4, 3}
local PROMO_B   = {11, 8, 10, 9}

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

function ChessBoard:new()
    local o = setmetatable({}, self)
    o.sq       = {}
    o.turn     = "w"
    o.castle   = { wK = true, wQ = true, bK = true, bQ = true }
    o.ep       = nil
    o.halfmove = 0
    o.selected = nil
    o.status   = "playing"
    o.winner   = nil
    o.draw_reason = nil
    o.last_move   = nil
    o._history = {}          -- undo stack: array of snapshots
    o._future  = {}          -- redo stack: array of snapshots
    o._move_history = {}     -- parallel to _history: array of { san, move }
    o._move_future  = {}     -- parallel to _future
    o._valid_moves_cache = nil
    o._selected_moves    = nil
    o.promo_pending      = nil
    o:reset()
    return o
end

-- ---------------------------------------------------------------------------
-- Reset to initial position
-- ---------------------------------------------------------------------------

function ChessBoard:reset()
    local sq = {}
    for r = 1, 8 do
        sq[r] = {}
        for c = 1, 8 do sq[r][c] = 0 end
    end
    -- Black back rank (r=1)
    sq[1][1]=8; sq[1][2]=9; sq[1][3]=10; sq[1][4]=11
    sq[1][5]=12; sq[1][6]=10; sq[1][7]=9; sq[1][8]=8
    -- Black pawns (r=2)
    for c = 1, 8 do sq[2][c] = 7 end
    -- White pawns (r=7)
    for c = 1, 8 do sq[7][c] = 1 end
    -- White back rank (r=8)
    sq[8][1]=2; sq[8][2]=3; sq[8][3]=4; sq[8][4]=5
    sq[8][5]=6; sq[8][6]=4; sq[8][7]=3; sq[8][8]=2

    self.sq       = sq
    self.turn     = "w"
    self.castle   = { wK = true, wQ = true, bK = true, bQ = true }
    self.ep       = nil
    self.halfmove = 0
    self.selected = nil
    self.status   = "playing"
    self.winner   = nil
    self.draw_reason = nil
    self.last_move   = nil
    self._history = {}
    self._future  = {}
    self._move_history = {}
    self._move_future  = {}
    self._valid_moves_cache = nil
    self._selected_moves    = nil
    self.promo_pending      = nil
end

-- ---------------------------------------------------------------------------
-- Find king
-- ---------------------------------------------------------------------------

function ChessBoard:findKing(color)
    local king = (color == "w") and 6 or 12
    for r = 1, 8 do
        for c = 1, 8 do
            if self.sq[r][c] == king then return r, c end
        end
    end
    return nil, nil
end

-- ---------------------------------------------------------------------------
-- Attack detection
-- ---------------------------------------------------------------------------

function ChessBoard:isAttacked(r, c, by_color)
    local sq = self.sq
    local opp_pawn   = (by_color == "w") and 1 or 7
    local opp_rook   = (by_color == "w") and 2 or 8
    local opp_knight = (by_color == "w") and 3 or 9
    local opp_bishop = (by_color == "w") and 4 or 10
    local opp_queen  = (by_color == "w") and 5 or 11
    local opp_king   = (by_color == "w") and 6 or 12

    -- Pawn attacks
    local pawn_dr = (by_color == "w") and 1 or -1
    -- A white pawn at (r+pawn_dr, c±1) attacks (r,c)
    -- i.e. if by_color=="w", white pawns move "upward" (r decreasing), so they attack from r+1
    -- if by_color=="b", black pawns move "downward" (r increasing), so they attack from r-1
    -- (Before 1.3.0 this looked on the wrong side, so pawn checks went unseen.)
    local pr = r + pawn_dr
    if pr >= 1 and pr <= 8 then
        if c > 1 and sq[pr][c - 1] == opp_pawn then return true end
        if c < 8 and sq[pr][c + 1] == opp_pawn then return true end
    end

    -- Knight attacks
    for i = 1, 8 do
        local kr2, kc2 = r + KN_DR[i], c + KN_DC[i]
        if inBoard(kr2, kc2) and sq[kr2][kc2] == opp_knight then return true end
    end

    -- Rook / Queen (orthogonal rays)
    for _, d in ipairs(DIRS_ORTH) do
        local rr, cc = r + d[1], c + d[2]
        while inBoard(rr, cc) do
            local piece = sq[rr][cc]
            if piece ~= 0 then
                if piece == opp_rook or piece == opp_queen then return true end
                break
            end
            rr = rr + d[1]; cc = cc + d[2]
        end
    end

    -- Bishop / Queen (diagonal rays)
    for _, d in ipairs(DIRS_DIAG) do
        local rr, cc = r + d[1], c + d[2]
        while inBoard(rr, cc) do
            local piece = sq[rr][cc]
            if piece ~= 0 then
                if piece == opp_bishop or piece == opp_queen then return true end
                break
            end
            rr = rr + d[1]; cc = cc + d[2]
        end
    end

    -- King attacks (1 step any direction)
    for dr = -1, 1 do
        for dc = -1, 1 do
            if dr ~= 0 or dc ~= 0 then
                local kr2, kc2 = r + dr, c + dc
                if inBoard(kr2, kc2) and sq[kr2][kc2] == opp_king then return true end
            end
        end
    end

    return false
end

function ChessBoard:isInCheck(color)
    local kr, kc = self:findKing(color)
    if not kr then return false end
    local opp = (color == "w") and "b" or "w"
    return self:isAttacked(kr, kc, opp)
end

-- ---------------------------------------------------------------------------
-- Pseudo-legal move generation
-- ---------------------------------------------------------------------------

-- With `captures_only`, only captures, en passant and promotions are listed
-- (the quiescence search's moves), in the same order as the full list.
function ChessBoard:_genPseudoMoves(color, captures_only)
    local moves = {}
    local sq    = self.sq
    local ep    = self.ep
    local castle = self.castle
    local own_lo = (color == "w") and 1 or 7
    local own_hi = own_lo + 5

    local function addMove(fr, fc, tr, tc, special, promo_piece)
        local capture = sq[tr][tc] ~= 0
        if captures_only and not capture then return end
        moves[#moves + 1] = {
            fr = fr, fc = fc, tr = tr, tc = tc,
            capture = capture,
            special = special,
            promo_piece = promo_piece,
        }
    end

    for r = 1, 8 do
        for c = 1, 8 do
            local piece = sq[r][c]
            if piece == 0 then goto continue end
            if pieceColor(piece) ~= color then goto continue end

            local pt = pieceType(piece)

            -- Pawn
            if pt == 1 then
                local dr  = (color == "w") and -1 or 1    -- white moves toward r=1
                local start_r = (color == "w") and 7 or 2
                local promo_r = (color == "w") and 1 or 8

                -- Forward 1
                local nr = r + dr
                if inBoard(nr, c) and sq[nr][c] == 0 then
                    if nr == promo_r then
                        -- Generate promotion for queen, rook, bishop, knight
                        for _, pp in ipairs((color == "w") and PROMO_W or PROMO_B) do
                            moves[#moves+1] = { fr=r, fc=c, tr=nr, tc=c, capture=false,
                                special="promo", promo_piece=pp }
                        end
                    elseif not captures_only then
                        addMove(r, c, nr, c)
                        -- Forward 2 from start
                        if r == start_r and sq[r + dr*2][c] == 0 then
                            addMove(r, c, r + dr*2, c)
                        end
                    end
                end

                -- Diagonal captures
                for _, dc in ipairs(PAWN_DCS) do
                    local nr2, nc2 = r + dr, c + dc
                    if inBoard(nr2, nc2) then
                        local target = sq[nr2][nc2]
                        if target ~= 0 and pieceColor(target) ~= color then
                            if nr2 == promo_r then
                                for _, pp in ipairs((color == "w") and PROMO_W or PROMO_B) do
                                    moves[#moves+1] = { fr=r, fc=c, tr=nr2, tc=nc2, capture=true,
                                        special="promo", promo_piece=pp }
                                end
                            else
                                addMove(r, c, nr2, nc2)
                            end
                        end
                        -- En passant
                        if ep and nc2 == ep and target == 0 then
                            local ep_rank = (color == "w") and 4 or 5  -- r=4 for white, r=5 for black
                            if r == ep_rank then
                                moves[#moves+1] = { fr=r, fc=c, tr=nr2, tc=nc2, capture=true,
                                    special="ep", promo_piece=nil }
                            end
                        end
                    end
                end

            -- Knight
            elseif pt == 3 then
                for i = 1, 8 do
                    local nr, nc = r + KN_DR[i], c + KN_DC[i]
                    if inBoard(nr, nc) then
                        local target = sq[nr][nc]
                        if target == 0 or pieceColor(target) ~= color then
                            addMove(r, c, nr, nc)
                        end
                    end
                end

            -- Bishop, rook, queen
            elseif pt == 4 or pt == 2 or pt == 5 then
                local dirs = (pt == 4) and DIRS_DIAG or (pt == 2) and DIRS_ORTH or DIRS_ALL
                for _, d in ipairs(dirs) do
                    local dr, dc = d[1], d[2]
                    local rr, cc = r + dr, c + dc
                    while rr >= 1 and rr <= 8 and cc >= 1 and cc <= 8 do
                        local target = sq[rr][cc]
                        if target ~= 0 then
                            if target < own_lo or target > own_hi then addMove(r, c, rr, cc) end
                            break
                        end
                        if not captures_only then addMove(r, c, rr, cc) end
                        rr = rr + dr; cc = cc + dc
                    end
                end

            -- King
            elseif pt == 6 then
                for dr = -1, 1 do
                    for dc = -1, 1 do
                        if dr ~= 0 or dc ~= 0 then
                            local nr, nc = r + dr, c + dc
                            if inBoard(nr, nc) then
                                local target = sq[nr][nc]
                                if target == 0 or pieceColor(target) ~= color then
                                    addMove(r, c, nr, nc)
                                end
                            end
                        end
                    end
                end

                -- Castling
                if captures_only then goto continue end
                local opp = (color == "w") and "b" or "w"
                local back_r = (color == "w") and 8 or 1

                if r == back_r and c == 5 then
                    -- Kingside
                    local ks_right = (color == "w") and castle.wK or castle.bK
                    if ks_right
                       and sq[back_r][6] == 0 and sq[back_r][7] == 0
                       and not self:isAttacked(back_r, 5, opp)
                       and not self:isAttacked(back_r, 6, opp)
                       and not self:isAttacked(back_r, 7, opp)
                    then
                        moves[#moves+1] = { fr=r, fc=c, tr=back_r, tc=7, capture=false,
                            special="castle_k", promo_piece=nil }
                    end
                    -- Queenside
                    local qs_right = (color == "w") and castle.wQ or castle.bQ
                    if qs_right
                       and sq[back_r][4] == 0 and sq[back_r][3] == 0 and sq[back_r][2] == 0
                       and not self:isAttacked(back_r, 5, opp)
                       and not self:isAttacked(back_r, 4, opp)
                       and not self:isAttacked(back_r, 3, opp)
                    then
                        moves[#moves+1] = { fr=r, fc=c, tr=back_r, tc=3, capture=false,
                            special="castle_q", promo_piece=nil }
                    end
                end
            end

            ::continue::
        end
    end
    return moves
end

-- ---------------------------------------------------------------------------
-- Apply / undo a move internally (for legality testing and AI)
-- Returns a small undo record (only what the move changes: no board copy,
-- so the AI search does not allocate a 64-square snapshot per node).
-- ---------------------------------------------------------------------------

function ChessBoard:_applyMove(move)
    local sq = self.sq
    local castle = self.castle
    local fr, fc, tr, tc = move.fr, move.fc, move.tr, move.tc
    local piece = sq[fr][fc]
    local saved = {
        move     = move,
        piece    = piece,
        captured = sq[tr][tc],
        turn     = self.turn,
        wK = castle.wK, wQ = castle.wQ, bK = castle.bK, bQ = castle.bQ,
        ep       = self.ep,
        halfmove = self.halfmove,
    }

    -- En passant capture
    if move.special == "ep" then
        local cap_r = (self.turn == "w") and (tr + 1) or (tr - 1)
        saved.ep_captured = sq[cap_r][tc]
        sq[cap_r][tc] = 0
    end

    -- Move piece
    sq[tr][tc] = (move.special == "promo") and move.promo_piece or piece
    sq[fr][fc] = 0

    -- Castling: move rook
    if move.special == "castle_k" then
        sq[tr][6] = sq[tr][8]; sq[tr][8] = 0
    elseif move.special == "castle_q" then
        sq[tr][4] = sq[tr][1]; sq[tr][1] = 0
    end

    -- Update castling rights
    local pt = pieceType(piece)
    if pt == 6 then
        if self.turn == "w" then castle.wK = false; castle.wQ = false
        else                     castle.bK = false; castle.bQ = false end
    elseif pt == 2 then
        if fr == 8 and fc == 1 then castle.wQ = false end
        if fr == 8 and fc == 8 then castle.wK = false end
        if fr == 1 and fc == 1 then castle.bQ = false end
        if fr == 1 and fc == 8 then castle.bK = false end
    end
    -- Also update if rook square is captured
    if tr == 8 and tc == 1 then castle.wQ = false end
    if tr == 8 and tc == 8 then castle.wK = false end
    if tr == 1 and tc == 1 then castle.bQ = false end
    if tr == 1 and tc == 8 then castle.bK = false end

    -- En passant target
    self.ep = nil
    if pt == 1 and math.abs(tr - fr) == 2 then
        self.ep = tc
    end

    -- Halfmove clock
    if pt == 1 or move.capture or move.special == "ep" then
        self.halfmove = 0
    else
        self.halfmove = self.halfmove + 1
    end

    self.turn = (self.turn == "w") and "b" or "w"

    return saved
end

function ChessBoard:_undoMove(saved)
    local sq, move = self.sq, saved.move
    local fr, fc, tr, tc = move.fr, move.fc, move.tr, move.tc
    if move.special == "castle_k" then
        sq[tr][8] = sq[tr][6]; sq[tr][6] = 0
    elseif move.special == "castle_q" then
        sq[tr][1] = sq[tr][4]; sq[tr][4] = 0
    elseif move.special == "ep" then
        local cap_r = (saved.turn == "w") and (tr + 1) or (tr - 1)
        sq[cap_r][tc] = saved.ep_captured
    end
    sq[tr][tc] = saved.captured
    sq[fr][fc] = saved.piece
    local castle = self.castle
    castle.wK, castle.wQ, castle.bK, castle.bQ = saved.wK, saved.wQ, saved.bK, saved.bQ
    self.turn     = saved.turn
    self.ep       = saved.ep
    self.halfmove = saved.halfmove
end

-- ---------------------------------------------------------------------------
-- Legal move generation
-- ---------------------------------------------------------------------------

function ChessBoard:_isMoveLegal(move)
    local saved  = self:_applyMove(move)
    -- After apply, turn flipped — check if the side that just moved left their king in check
    local mover  = saved.turn
    local kr, kc = self:findKing(mover)
    local ok = kr and not self:isAttacked(kr, kc, self.turn)  -- self.turn is now opponent
    self:_undoMove(saved)
    return ok
end

function ChessBoard:getLegalMoves()
    local pseudo = self:_genPseudoMoves(self.turn)
    local legal  = {}
    for _, m in ipairs(pseudo) do
        if self:_isMoveLegal(m) then
            legal[#legal + 1] = m
        end
    end
    return legal
end

function ChessBoard:getMovesForSquare(r, c)
    if not self._valid_moves_cache then
        self._valid_moves_cache = self:getLegalMoves()
    end
    local result = {}
    for _, m in ipairs(self._valid_moves_cache) do
        if m.fr == r and m.fc == c then
            result[#result + 1] = m
        end
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Draw detection helpers
-- ---------------------------------------------------------------------------

-- True when neither side has enough material to ever force checkmate:
-- K vs K, K+minor vs K, or K+B vs K+B with same-coloured-square bishops.
-- Any pawn, rook, or queen on the board disqualifies (mate is still possible).
local function hasInsufficientMaterial(sq)
    local w_minors, b_minors = {}, {}
    for r = 1, 8 do
        for c = 1, 8 do
            local p = sq[r][c]
            if p ~= 0 then
                local pt = pieceType(p)
                if pt == 1 or pt == 2 or pt == 5 then
                    return false  -- pawn, rook or queen present
                elseif pt == 3 or pt == 4 then  -- knight or bishop
                    local entry = { pt = pt, sq_color = (r + c) % 2 }
                    if isWhite(p) then
                        w_minors[#w_minors + 1] = entry
                    else
                        b_minors[#b_minors + 1] = entry
                    end
                end
            end
        end
    end
    if #w_minors == 0 and #b_minors == 0 then return true end        -- K vs K
    if #w_minors == 1 and #b_minors == 0 then return true end        -- K+minor vs K
    if #w_minors == 0 and #b_minors == 1 then return true end
    if #w_minors == 1 and #b_minors == 1 then
        local wm, bm = w_minors[1], b_minors[1]
        return wm.pt == 4 and bm.pt == 4 and wm.sq_color == bm.sq_color  -- same-colour bishops
    end
    return false
end

-- Build a key identifying a position for threefold-repetition purposes:
-- piece placement + side to move + castling rights + en-passant file.
local function positionKeyFromFlat(flat, turn, castle, ep)
    local parts = {}
    for i = 1, 64 do parts[i] = flat[i] end
    parts[65] = turn
    parts[66] = castle.wK and 1 or 0
    parts[67] = castle.wQ and 1 or 0
    parts[68] = castle.bK and 1 or 0
    parts[69] = castle.bQ and 1 or 0
    parts[70] = ep or 0
    return table.concat(parts, ",")
end

function ChessBoard:_currentFlat()
    local flat = {}
    for r = 1, 8 do
        for c = 1, 8 do
            flat[(r - 1) * 8 + c] = self.sq[r][c]
        end
    end
    return flat
end

-- Counts how many times the current position has occurred so far, by
-- replaying it against every position stored in the undo stack (each
-- snapshot there is the position immediately before the corresponding
-- move was played, so together with the live position they cover every
-- distinct position reached since the game started / was loaded).
function ChessBoard:_countRepetitions()
    local cur_key = positionKeyFromFlat(self:_currentFlat(), self.turn, self.castle, self.ep)
    local count = 1
    for _, snap in ipairs(self._history) do
        local key = positionKeyFromFlat(snap.sq_flat, snap.turn, snap.castle, snap.ep)
        if key == cur_key then count = count + 1 end
    end
    return count
end

-- ---------------------------------------------------------------------------
-- Game end detection
-- ---------------------------------------------------------------------------

function ChessBoard:_updateStatus()
    local legal = self:getLegalMoves()
    local in_check = self:isInCheck(self.turn)
    if #legal == 0 then
        if in_check then
            self.status = "checkmate"
            self.winner = (self.turn == "w") and "b" or "w"
        else
            self.status = "stalemate"
            self.winner = nil
        end
        self.draw_reason = nil
    elseif self.halfmove >= 100 then
        self.status = "draw"
        self.winner = nil
        self.draw_reason = "fifty_move"
    elseif hasInsufficientMaterial(self.sq) then
        self.status = "draw"
        self.winner = nil
        self.draw_reason = "insufficient_material"
    elseif self:_countRepetitions() >= 3 then
        self.status = "draw"
        self.winner = nil
        self.draw_reason = "repetition"
    else
        self.status = "playing"
        self.winner = nil
        self.draw_reason = nil
    end
    -- Invalidate move cache (it was used above, now stale)
    self._valid_moves_cache = nil
end

-- ---------------------------------------------------------------------------
-- Undo/redo snapshot helpers
-- ---------------------------------------------------------------------------

function ChessBoard:_captureSnapshot()
    return {
        sq_flat  = self:_currentFlat(),
        turn     = self.turn,
        castle   = { wK=self.castle.wK, wQ=self.castle.wQ,
                     bK=self.castle.bK, bQ=self.castle.bQ },
        ep          = self.ep,
        halfmove    = self.halfmove,
        status      = self.status,
        winner      = self.winner,
        draw_reason = self.draw_reason,
    }
end

function ChessBoard:_restoreSnapshot(snap)
    for r = 1, 8 do
        for c = 1, 8 do
            self.sq[r][c] = snap.sq_flat[(r-1)*8+c]
        end
    end
    self.turn        = snap.turn
    self.castle      = snap.castle
    self.ep          = snap.ep
    self.halfmove    = snap.halfmove
    self.status      = snap.status
    self.winner      = snap.winner
    self.draw_reason = snap.draw_reason
    self.selected = nil
    self._valid_moves_cache = nil
    self._selected_moves    = nil
    self.promo_pending      = nil
end

-- ---------------------------------------------------------------------------
-- Public makeMove
-- ---------------------------------------------------------------------------

function ChessBoard:makeMove(fr, fc, tr, tc, promo_piece)
    if self.status ~= "playing" then return false end

    -- Find matching legal move
    local legal = self:getLegalMoves()
    local found = nil
    for _, m in ipairs(legal) do
        if m.fr == fr and m.fc == fc and m.tr == tr and m.tc == tc then
            -- For promotions, match promo_piece (default queen if nil)
            if m.special == "promo" then
                local desired = promo_piece
                    or ((self.turn == "w") and ChessBoard.W_QUEEN or ChessBoard.B_QUEEN)
                if m.promo_piece == desired then
                    found = m
                    break
                end
            else
                found = m
                break
            end
        end
    end
    if not found then return false end

    -- SAN must be computed before the move is applied (disambiguation needs
    -- the pre-move position); toSAN applies/undoes internally to detect check.
    local san = PGN.toSAN(self, found)

    -- Save snapshot for undo; a fresh move invalidates any redo line.
    self._history[#self._history + 1] = self:_captureSnapshot()
    self._move_history[#self._move_history + 1] = { san = san, move = found }
    self._future = {}
    self._move_future = {}

    -- Apply move
    self:_applyMove(found)
    self.last_move = found

    self.selected = nil
    self._valid_moves_cache = nil
    self._selected_moves    = nil
    self.promo_pending      = nil

    self:_updateStatus()
    return true
end

-- Finds the legal move matching a SAN token (e.g. "Nf3", "exd5", "O-O",
-- "e8=Q") in the current position and plays it via makeMove.
function ChessBoard:makeMoveSAN(san)
    local move = PGN.findMoveForSAN(self, san)
    if not move then return false end
    return self:makeMove(move.fr, move.fc, move.tr, move.tc, move.promo_piece)
end

-- ---------------------------------------------------------------------------
-- Undo / redo
-- ---------------------------------------------------------------------------

function ChessBoard:undoMove()
    if #self._history == 0 then return false end
    self._future[#self._future + 1] = self:_captureSnapshot()
    self._move_future[#self._move_future + 1] = table.remove(self._move_history)
    self:_restoreSnapshot(table.remove(self._history))
    local top = self._move_history[#self._move_history]
    self.last_move = top and top.move or nil
    return true
end

function ChessBoard:redoMove()
    if #self._future == 0 then return false end
    self._history[#self._history + 1] = self:_captureSnapshot()
    local entry = table.remove(self._move_future)
    self._move_history[#self._move_history + 1] = entry
    self:_restoreSnapshot(table.remove(self._future))
    self.last_move = entry.move
    return true
end

-- ---------------------------------------------------------------------------
-- tapCell — UI interaction handler
-- ---------------------------------------------------------------------------

function ChessBoard:tapCell(r, c)
    if self.status ~= "playing" then return "invalid" end

    local sq = self.sq
    local piece = sq[r][c]

    -- If a promotion is pending, ignore taps until resolved
    if self.promo_pending then return "invalid" end

    if self.selected then
        local sr, sc = self.selected.r, self.selected.c

        -- Clicking the same selected square: deselect
        if r == sr and c == sc then
            self.selected = nil
            self._selected_moves = nil
            return "deselect"
        end

        -- Clicking another own piece: re-select
        if piece ~= 0 and pieceColor(piece) == self.turn then
            self.selected = { r = r, c = c }
            self._selected_moves = self:getMovesForSquare(r, c)
            return "select"
        end

        -- Check if this is a valid target for selected piece
        local moves = self._selected_moves or self:getMovesForSquare(sr, sc)
        local matching = {}
        for _, m in ipairs(moves) do
            if m.tr == r and m.tc == c then
                matching[#matching+1] = m
            end
        end

        if #matching == 0 then
            self.selected = nil
            self._selected_moves = nil
            return "deselect"
        end

        -- Check if promotion
        local is_promo = (matching[1].special == "promo")
        if is_promo and #matching > 1 then
            -- Multiple promotion options — need human to choose
            self.promo_pending = { fr=sr, fc=sc, tr=r, tc=c }
            return "promo_needed"
        end

        -- Make the move (single match or AI auto-queen)
        local promo = matching[1].promo_piece
        self:makeMove(sr, sc, r, c, promo)
        return "move"
    else
        -- No selection
        if piece ~= 0 and pieceColor(piece) == self.turn then
            self.selected = { r = r, c = c }
            self._selected_moves = self:getMovesForSquare(r, c)
            return "select"
        end
        return "invalid"
    end
end

function ChessBoard:finishPromo(piece_val)
    if not self.promo_pending then return false end
    local p = self.promo_pending
    self.promo_pending = nil
    self.selected = nil
    self._selected_moves = nil
    return self:makeMove(p.fr, p.fc, p.tr, p.tc, piece_val)
end

-- ---------------------------------------------------------------------------
-- Serialization
-- ---------------------------------------------------------------------------

local function serializeSnapshots(list)
    local out = {}
    for i, snap in ipairs(list) do
        local h = {}
        h.sq_flat  = {}
        for k, v in pairs(snap.sq_flat) do h.sq_flat[k] = v end
        h.turn        = snap.turn
        h.castle      = { wK=snap.castle.wK, wQ=snap.castle.wQ,
                          bK=snap.castle.bK, bQ=snap.castle.bQ }
        h.ep          = snap.ep
        h.halfmove    = snap.halfmove
        h.status      = snap.status
        h.winner      = snap.winner
        h.draw_reason = snap.draw_reason
        out[i] = h
    end
    return out
end

local function deserializeSnapshots(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, h in ipairs(list) do
        local snap = {
            sq_flat     = {},
            turn        = h.turn,
            castle      = { wK=h.castle.wK, wQ=h.castle.wQ,
                            bK=h.castle.bK, bQ=h.castle.bQ },
            ep          = h.ep,
            halfmove    = h.halfmove,
            status      = h.status,
            winner      = h.winner,
            draw_reason = h.draw_reason,
        }
        for k, v in pairs(h.sq_flat) do snap.sq_flat[k] = v end
        out[#out+1] = snap
    end
    return out
end

local function copyMoveLog(list)
    local out = {}
    for i, entry in ipairs(list) do
        local move_copy = {}
        for k, v in pairs(entry.move) do move_copy[k] = v end
        out[i] = { san = entry.san, move = move_copy }
    end
    return out
end

function ChessBoard:serialize()
    return {
        sq_flat      = self:_currentFlat(),
        turn         = self.turn,
        castle       = { wK=self.castle.wK, wQ=self.castle.wQ,
                         bK=self.castle.bK, bQ=self.castle.bQ },
        ep           = self.ep,
        halfmove     = self.halfmove,
        status       = self.status,
        winner       = self.winner,
        draw_reason  = self.draw_reason,
        history      = serializeSnapshots(self._history),
        future       = serializeSnapshots(self._future),
        move_history = copyMoveLog(self._move_history),
        move_future  = copyMoveLog(self._move_future),
    }
end

function ChessBoard:load(data)
    if type(data) ~= "table" or type(data.sq_flat) ~= "table" then return false end
    for r = 1, 8 do
        if not self.sq[r] then self.sq[r] = {} end
        for c = 1, 8 do
            self.sq[r][c] = data.sq_flat[(r-1)*8+c] or 0
        end
    end
    self.turn     = data.turn     or "w"
    self.castle   = data.castle
        and { wK=data.castle.wK~=false, wQ=data.castle.wQ~=false,
              bK=data.castle.bK~=false, bQ=data.castle.bQ~=false }
        or  { wK=true, wQ=true, bK=true, bQ=true }
    self.ep          = data.ep
    self.halfmove    = data.halfmove or 0
    self.status      = data.status   or "playing"
    self.winner      = data.winner
    self.draw_reason = data.draw_reason
    self._history = deserializeSnapshots(data.history)
    self._future  = deserializeSnapshots(data.future)
    self._move_history = copyMoveLog(data.move_history or {})
    self._move_future  = copyMoveLog(data.move_future or {})
    local top = self._move_history[#self._move_history]
    self.last_move = top and top.move or nil
    self.selected = nil
    self._valid_moves_cache = nil
    self._selected_moves    = nil
    self.promo_pending      = nil
    return true
end

-- ---------------------------------------------------------------------------
-- AI — alpha-beta + quiescence search + killer moves + improved evaluation
-- ---------------------------------------------------------------------------

-- True when queens are off the board or total minor/major material is low
local function isEndgame(sq)
    local mat_w, mat_b = 0, 0
    local has_wq, has_bq = false, false
    for r = 1, 8 do
        for c = 1, 8 do
            local p = sq[r][c]
            if p == 5  then has_wq = true end
            if p == 11 then has_bq = true end
            if p >= 1 and p <= 5  then mat_w = mat_w + MAT[p]       end  -- white non-king
            if p >= 7 and p <= 11 then mat_b = mat_b - MAT[p]       end  -- black non-king (MAT<0)
        end
    end
    return (not has_wq and not has_bq) or (mat_w < 1300 and mat_b < 1300)
end

local function pstBonus(piece, r, c, eg)
    if piece == 0 then return 0 end
    local pt    = pieceType(piece)
    local is_w  = isWhite(piece)
    local row_idx = is_w and (9 - r) or r
    local sign    = is_w and 1 or -1

    local pst
    if     pt == 1 then pst = PST_PAWN
    elseif pt == 2 then pst = PST_ROOK
    elseif pt == 3 then pst = PST_KNIGHT
    elseif pt == 4 then pst = PST_BISHOP
    elseif pt == 5 then pst = PST_QUEEN
    elseif pt == 6 then pst = eg and PST_KING_EG or PST_KING_MG
    else return 0 end

    local row = pst[row_idx]
    if not row then return 0 end
    return sign * (row[c] or 0)
end

-- Piece-square table per piece code (kings handled apart: their table
-- depends on the game phase).
local PST_OF = { PST_PAWN, PST_ROOK, PST_KNIGHT, PST_BISHOP, PST_QUEEN }

-- Same score as summing MAT + pstBonus over the board, with isEndgame()
-- folded into the same single pass.
local function evalScan(self)
    local sq  = self.sq
    local wkr, wkc, bkr, bkc = 1, 1, 1, 1
    local score = 0
    local wb, bb = 0, 0
    local has_wq, has_bq = false, false
    local mat_w, mat_b = 0, 0
    local king_mg, king_eg = 0, 0
    for r = 1, 8 do
        local row = sq[r]
        for c = 1, 8 do
            local p = row[c]
            if p ~= 0 then
                score = score + MAT[p]
                if p <= 6 then
                    if p == 6 then
                        wkr, wkc = r, c
                        king_mg = king_mg + PST_KING_MG[9 - r][c]
                        king_eg = king_eg + PST_KING_EG[9 - r][c]
                    else
                        score = score + PST_OF[p][9 - r][c]
                        mat_w = mat_w + MAT[p]
                        if p == 5 then has_wq = true elseif p == 4 then wb = wb + 1 end
                    end
                else
                    if p == 12 then
                        bkr, bkc = r, c
                        king_mg = king_mg - PST_KING_MG[r][c]
                        king_eg = king_eg - PST_KING_EG[r][c]
                    else
                        score = score - PST_OF[p - 6][r][c]
                        mat_b = mat_b - MAT[p]
                        if p == 11 then has_bq = true elseif p == 10 then bb = bb + 1 end
                    end
                end
            end
        end
    end
    local eg = (not has_wq and not has_bq) or (mat_w < 1300 and mat_b < 1300)
    score = score + (eg and king_eg or king_mg)
    if wb >= 2 then score = score + 30 end   -- bishop pair bonus
    if bb >= 2 then score = score - 30 end
    return score, mat_w, mat_b, wkr, wkc, bkr, bkc
end

function ChessBoard:_evaluate()
    return (evalScan(self))
end

-- Distance of a square from the centre: 0 on d4/e5, 6 in a corner.
local function centreDist(r, c)
    return (math.abs(2 * r - 9) + math.abs(2 * c - 9) - 2) / 2
end

-- The search's evaluation: _evaluate() plus what it takes to convert a won
-- endgame instead of shuffling pieces until a draw.
--  * Mop-up: once one side is a piece or more ahead and the other has
--    little left, drive the losing king to the edge and bring the winning
--    king close (KQK, KRK, ... are otherwise invisible to a short search).
--  * Progress: past 20 reversible half-moves the score shrinks towards 0,
--    so the side that is ahead prefers captures and pawn moves to a
--    fifty-move draw.
function ChessBoard:_searchEval()
    local score, mat_w, mat_b, wkr, wkc, bkr, bkc = evalScan(self)
    local diff = mat_w - mat_b
    if diff >= 400 and mat_b <= 1300 then
        score = score + 20 * centreDist(bkr, bkc)
              + 10 * (14 - math.abs(wkr - bkr) - math.abs(wkc - bkc))
    elseif diff <= -400 and mat_w <= 1300 then
        score = score - 20 * centreDist(wkr, wkc)
              - 10 * (14 - math.abs(wkr - bkr) - math.abs(wkc - bkc))
    end
    local hm = self.halfmove
    if hm > 20 then score = math.floor(score * (100 - (hm - 20)) / 100 + 0.5) end
    return score
end

-- Reference version of _evaluate() (the straightforward double scan), kept
-- for the regression spec that checks the two always agree.
function ChessBoard:_evaluateReference()
    local sq  = self.sq
    local eg  = isEndgame(sq)
    local score = 0
    local wb, bb = 0, 0
    for r = 1, 8 do
        for c = 1, 8 do
            local p = sq[r][c]
            if p ~= 0 then
                score = score + MAT[p] + pstBonus(p, r, c, eg)
                if p == 4  then wb = wb + 1 end   -- white bishop
                if p == 10 then bb = bb + 1 end   -- black bishop
            end
        end
    end
    if wb >= 2 then score = score + 30 end   -- bishop pair bonus
    if bb >= 2 then score = score - 30 end
    return score
end

-- ---------------------------------------------------------------------------
-- Search budget
--
-- Each level searches to a fixed maximum depth (the depth it always played
-- at) by iterative deepening, but stops once its CPU budget is spent and
-- plays the best move of the deepest finished iteration. The budgets are in
-- seconds of a Kobo-class e-reader (1 GHz single core); a desktop reaches the
-- maximum depth long before. AI_TIME_SCALE lets tests and benchmarks
-- simulate a slower device (e.g. 0.04 ≈ a Kobo on a fast laptop).
-- ---------------------------------------------------------------------------

-- Easy also plays loosely, like a casual player: it picks at random among
-- the moves within `margin` centipawns of its best and, with probability
-- `blunder`, among those within `blunder_margin` (it can drop a piece). It
-- still plays a mate it sees. Hard's budget leaves room for the move
-- generation around the search so the whole move stays under 2.5 s.
ChessBoard.AI_LEVELS = {
    easy   = { depth = 1, budget = 0.4, margin = 250, blunder = 0.5, blunder_margin = 1000 },
    medium = { depth = 2, budget = 1.5 },
    hard   = { depth = 4, budget = 2.3 },
}
ChessBoard.AI_TIME_SCALE = 1

local clock = os.clock
local AI_ABORT = {}           -- error value thrown when the budget runs out
local ai_deadline = math.huge -- no deadline outside a budgeted search
local ai_countdown = 128      -- nodes until the next clock check

-- Repetition: an additive Zobrist-style hash per position (random 31-bit
-- keys from a fixed LCG, so sums stay exact in a double). ai_rep holds the
-- positions of the game since the last capture or pawn move plus those on
-- the current search line; reaching one again scores as a draw.
local ZOB = {}
do
    local x = 20261105
    for i = 1, 64 * 13 + 1 do
        x = (x * 1103515245 + 12345) % 2147483648
        ZOB[i] = x
    end
end
local ZOB_BLACK = ZOB[64 * 13 + 1]
local ai_rep = {}
local ai_max_ply = 8

local function hashFlat(flat, turn)
    local h = (turn == "b") and ZOB_BLACK or 0
    for i = 1, 64 do
        local p = flat[i]
        if p ~= 0 then h = h + ZOB[(i - 1) * 13 + p + 1] end
    end
    return h
end

function ChessBoard:_hash()
    local sq = self.sq
    local h = (self.turn == "b") and ZOB_BLACK or 0
    for r = 1, 8 do
        local row, base = sq[r], (r - 1) * 104
        for c = 1, 8 do
            local p = row[c]
            if p ~= 0 then h = h + ZOB[base + (c - 1) * 13 + p + 1] end
        end
    end
    return h
end

-- True when `color` has nothing but its king and pawns (where stalemate
-- becomes a real risk and is worth testing for at the search horizon).
function ChessBoard:_kingAndPawnsOnly(color)
    local sq = self.sq
    local lo, hi = (color == "w") and 2 or 8, (color == "w") and 5 or 11
    for r = 1, 8 do
        local row = sq[r]
        for c = 1, 8 do
            local p = row[c]
            if p >= lo and p <= hi then return false end
        end
    end
    return true
end

function ChessBoard:_hasLegalMove()
    local kr, kc = self:findKing(self.turn)
    for _, m in ipairs(self:_genPseudoMoves(self.turn)) do
        local saved = self:_applyIfLegal(m, kr, kc)
        if saved then self:_undoMove(saved); return true end
    end
    return false
end

local function aiTick()
    ai_countdown = ai_countdown - 1
    if ai_countdown <= 0 then
        ai_countdown = 128
        if clock() > ai_deadline then error(AI_ABORT, 0) end
    end
end

-- Move ordering: promotions > captures (MVV-LVA) > killers > quiet.
-- Scores are computed once per move (not inside the sort comparator).
local function moveScore(move, sq, killers)
    if move.special == "promo"  then return 9000 end
    if move.capture or move.special == "ep" then
        local v = math.abs(MAT[sq[move.tr][move.tc]] or 0)
        local a = math.abs(MAT[sq[move.fr][move.fc]] or 0)
        return 1000 + v * 10 - a
    end
    if killers then
        local k1, k2 = killers[1], killers[2]
        if k1 and k1.fr==move.fr and k1.fc==move.fc
              and k1.tr==move.tr and k1.tc==move.tc then return 900 end
        if k2 and k2.fr==move.fr and k2.fc==move.fc
              and k2.tr==move.tr and k2.tc==move.tc then return 899 end
    end
    return 0
end

local function byOrder(a, b) return a.order > b.order end

local function sortMoves(moves, sq, killers)
    for i = 1, #moves do
        local m = moves[i]
        m.order = moveScore(m, sq, killers)
    end
    table.sort(moves, byOrder)
end

-- Two killer slots per depth level (reset each root search)
local ai_killers = {}

local function storeKiller(depth, move)
    if move.capture or move.special then return end   -- only quiet moves
    if not ai_killers[depth] then ai_killers[depth] = {} end
    local k = ai_killers[depth]
    if k[1] and k[1].fr==move.fr and k[1].fc==move.fc
           and k[1].tr==move.tr and k[1].tc==move.tc then return end
    k[2] = k[1]
    k[1] = move
end

-- Applies a pseudo-legal move during search; returns the undo record, or nil
-- (with the board unchanged) when it would leave the mover's king in check.
-- (kr, kc) is the mover's king square before the move.
function ChessBoard:_applyIfLegal(m, kr, kc)
    local sq = self.sq
    if sq[m.fr][m.fc] % 6 == 0 then kr, kc = m.tr, m.tc end  -- king moves (6, 12)
    local saved = self:_applyMove(m)
    if self:isAttacked(kr, kc, self.turn) then   -- self.turn is now the opponent
        self:_undoMove(saved)
        return nil
    end
    return saved
end

-- Quiescence search: resolve captures/promotions before evaluating statically.
-- Prevents the horizon effect (e.g. "winning" a queen on move N then losing the
-- king on move N+1 being invisible at depth 0).
function ChessBoard:_quiescence(alpha, beta)
    aiTick()
    local maximizing = (self.turn == "w")
    local stand_pat  = self:_searchEval()

    if maximizing then
        if stand_pat >= beta  then return beta  end
        if stand_pat > alpha  then alpha = stand_pat end
    else
        if stand_pat <= alpha then return alpha end
        if stand_pat < beta   then beta  = stand_pat end
    end

    local caps = self:_genPseudoMoves(self.turn, true)
    if #caps == 0 then return maximizing and alpha or beta end
    sortMoves(caps, self.sq, nil)
    local kr, kc = self:findKing(self.turn)

    if maximizing then
        for _, m in ipairs(caps) do
            local saved = self:_applyIfLegal(m, kr, kc)
            if saved then
                local score = self:_quiescence(alpha, beta)
                self:_undoMove(saved)
                if score >= beta then return beta  end
                if score > alpha then alpha = score end
            end
        end
        return alpha
    else
        for _, m in ipairs(caps) do
            local saved = self:_applyIfLegal(m, kr, kc)
            if saved then
                local score = self:_quiescence(alpha, beta)
                self:_undoMove(saved)
                if score <= alpha then return alpha end
                if score < beta   then beta  = score end
            end
        end
        return beta
    end
end

-- Legality is tested lazily, move by move, so the moves a cutoff skips are
-- never checked at all; mate / stalemate is detected when none was legal.
-- At the horizon a side in check gets one more ply (so a mate there is seen
-- as a mate), and a bare king (or king and pawns) is tested for stalemate.
-- A position already met in the game or on the search line is a draw.
function ChessBoard:_alphaBeta(depth, alpha, beta, maximizing, ply)
    ply = ply or 1
    aiTick()

    if self.halfmove >= 100 then
        if #self:getLegalMoves() == 0 then
            if self:isInCheck(self.turn) then
                return (maximizing and -(30000 + depth) or (30000 + depth)), nil
            end
        end
        return 0, nil
    end

    local h
    if depth > 0 or self.halfmove >= 4 then
        h = self:_hash()
        if ai_rep[h] then return 0, nil end
    end

    if depth <= 0 then
        if ply < ai_max_ply and self:isInCheck(self.turn) then
            depth = 1
        else
            if self:_kingAndPawnsOnly(self.turn) and not self:_hasLegalMove() then
                return 0, nil
            end
            return self:_quiescence(alpha, beta), nil
        end
    end

    if not h then h = self:_hash() end
    ai_rep[h] = true
    local val, mv = self:_alphaBetaMoves(depth, alpha, beta, maximizing, ply)
    ai_rep[h] = nil
    return val, mv
end

function ChessBoard:_alphaBetaMoves(depth, alpha, beta, maximizing, ply)
    local moves = self:_genPseudoMoves(self.turn)
    sortMoves(moves, self.sq, ai_killers[depth])
    local kr, kc = self:findKing(self.turn)

    local best_move = nil
    local best_val = maximizing and -math.huge or math.huge
    for _, m in ipairs(moves) do
        local saved = self:_applyIfLegal(m, kr, kc)
        if saved then
            local val = self:_alphaBeta(depth - 1, alpha, beta, not maximizing, ply + 1)
            self:_undoMove(saved)
            if maximizing then
                if val > best_val then best_val = val; best_move = m end
                if val > alpha    then alpha = val end
            else
                if val < best_val then best_val = val; best_move = m end
                if val < beta     then beta = val end
            end
            if beta <= alpha then storeKiller(depth, m); break end
        end
    end
    if not best_move then
        -- Mated: scored by the remaining depth, so a quicker mate is worth
        -- more (otherwise every mate ties and the AI can dawdle forever).
        if self:isInCheck(self.turn) then
            return (maximizing and -(30000 + depth) or (30000 + depth)), nil
        end
        return 0, nil  -- stalemate
    end
    return best_val, best_move
end

-- One root iteration at `depth`. Fills `vals[i]` for each root move it
-- finishes and returns the best value and every move tied at it.
function ChessBoard:_searchRoot(legal, depth, maximizing, vals, exact)
    local best_val   = maximizing and -math.huge or math.huge
    local best_moves = {}

    -- Carrying the running best into the window is what lets the root prune at
    -- all; a fresh (-inf, +inf) per move discards every cutoff between
    -- siblings. The window is widened by one either way so that a move scoring
    -- *exactly* the current best still comes back with its true value instead
    -- of failing low -- otherwise the tie collection above, and the variety it
    -- buys, would quietly stop working. Safe because _evaluate() is integral.
    for i, m in ipairs(legal) do
        local alpha = maximizing and (best_val - 1) or -math.huge
        local beta  = maximizing and math.huge or (best_val + 1)
        if exact or best_val == math.huge or best_val == -math.huge then
            alpha, beta = -math.huge, math.huge
        end
        local saved = self:_applyMove(m)
        local val   = self:_alphaBeta(depth - 1, alpha, beta, not maximizing, 1)
        self:_undoMove(saved)
        vals[i] = val
        if maximizing then
            if val > best_val then
                best_val = val; best_moves = { m }
            elseif val == best_val then
                best_moves[#best_moves + 1] = m
            end
        else
            if val < best_val then
                best_val = val; best_moves = { m }
            elseif val == best_val then
                best_moves[#best_moves + 1] = m
            end
        end
    end
    return best_val, best_moves
end

-- Returns the AI's move: iterative deepening up to `depth` plies (plus
-- quiescence), stopping early after `budget` seconds (scaled by
-- AI_TIME_SCALE; nil = no limit). Always returns a legal move when one exists.
function ChessBoard:getAIMove(depth, budget, opts)
    depth = depth or 3
    opts = opts or {}
    if self.status ~= "playing" then return nil end

    ai_killers = {}  -- reset killer table for this search
    ai_countdown = 128
    ai_max_ply = depth + 6
    -- Positions since the last capture or pawn move (each snapshot is the
    -- position before a move), and the root itself.
    ai_rep = {}
    local hist = self._history
    for k = math.max(1, #hist - self.halfmove + 1), #hist do
        ai_rep[hashFlat(hist[k].sq_flat, hist[k].turn)] = true
    end
    ai_rep[self:_hash()] = true
    local noisy = opts.margin ~= nil
    local final_vals, final_legal

    local maximizing = (self.turn == "w")
    local legal = self:getLegalMoves()
    if #legal == 0 then return nil end

    sortMoves(legal, self.sq, nil)
    local chosen = { legal[1] }   -- fallback if not even depth 1 finishes

    local root = self:_captureSnapshot()
    ai_deadline = budget and (clock() + budget * ChessBoard.AI_TIME_SCALE) or math.huge
    self.ai_depth_reached = 0
    for d = 1, depth do
        local vals = {}
        local ok, best_val, best_moves = pcall(self._searchRoot, self, legal, d, maximizing, vals, noisy)
        if not ok then
            if best_val ~= AI_ABORT then
                ai_deadline = math.huge
                error(best_val, 0)
            end
            -- Out of time: undo the interrupted line. Root moves finished in
            -- this iteration were searched best-first, so the leader so far
            -- is at least as good as the previous iteration's choice.
            self:_restoreSnapshot(root)
            local done = #vals
            if done > 0 then
                local bv = vals[1]
                for i = 2, done do
                    if (maximizing and vals[i] > bv) or (not maximizing and vals[i] < bv) then bv = vals[i] end
                end
                if bv ~= vals[1] then
                    for i = 2, done do
                        if vals[i] == bv then chosen = { legal[i] }; break end
                    end
                end
            end
            break
        end
        chosen = best_moves
        final_vals, final_legal = vals, legal
        self.ai_depth_reached = d
        -- Next iteration: best root moves first (stable on equal values).
        local idx = {}
        for i = 1, #legal do idx[i] = i end
        table.sort(idx, function(a, b)
            if vals[a] ~= vals[b] then
                if maximizing then return vals[a] > vals[b] end
                return vals[a] < vals[b]
            end
            return a < b
        end)
        local reordered = {}
        for i = 1, #idx do reordered[i] = legal[idx[i]] end
        legal = reordered
    end
    ai_deadline = math.huge
    ai_rep = {}

    -- Root scores of the deepest finished iteration, by "fr,fc,tr,tc"
    -- (exact for a noisy level, bounds otherwise): for tests and debugging.
    self.ai_root_values = {}
    if final_vals then
        for i, m in ipairs(final_legal) do
            if final_vals[i] then
                self.ai_root_values[m.fr .. "," .. m.fc .. "," .. m.tr .. "," .. m.tc] = final_vals[i]
            end
        end
    end

    local best_move = chosen[math.random(#chosen)]
    if noisy and final_vals then
        best_move = self:_noisyChoice(final_legal, final_vals, maximizing, opts) or best_move
    end
    if best_move and best_move.special == "promo" then
        best_move.promo_piece = (self.turn == "w") and ChessBoard.W_QUEEN or ChessBoard.B_QUEEN
    end
    return best_move
end

-- Easy's looser choice among exactly scored root moves: any move within
-- `margin` of the best, or (probability `blunder`) within `blunder_margin`.
-- A found mate is always played. Draws from math.random.
function ChessBoard:_noisyChoice(legal, vals, maximizing, opts)
    local sign = maximizing and 1 or -1
    local best = -math.huge
    for i = 1, #legal do
        if vals[i] and sign * vals[i] > best then best = sign * vals[i] end
    end
    if best >= 30000 then return nil end
    local margin = opts.margin
    if opts.blunder and math.random() < opts.blunder then
        margin = opts.blunder_margin or margin
    end
    local pool = {}
    for i = 1, #legal do
        if vals[i] and sign * vals[i] >= best - margin then pool[#pool + 1] = legal[i] end
    end
    if #pool == 0 then return nil end
    return pool[math.random(#pool)]
end

-- Plays at a named level ("easy" / "medium" / "hard"), within its budget.
function ChessBoard:getAIMoveForLevel(level)
    local L = ChessBoard.AI_LEVELS[level] or ChessBoard.AI_LEVELS.medium
    return self:getAIMove(L.depth, L.budget, L)
end

return ChessBoard
