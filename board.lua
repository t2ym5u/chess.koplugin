-- ---------------------------------------------------------------------------
-- ChessBoard — complete chess engine for echecs.koplugin
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

-- Material values indexed by piece (white positive, black negative)
local MAT = { 0, 100, 500, 320, 330, 900, 20000, -100, -500, -320, -330, -900, -20000 }

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
    o._history = {}          -- undo stack: array of snapshots
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
    self._history = {}
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
    local pawn_dr = (by_color == "w") and 1 or -1  -- white pawns attack upward (r decreasing for black's king)
    -- A white pawn at (r+pawn_dr, c±1) attacks (r,c)
    -- i.e. if by_color=="w", white pawns move "upward" (r decreasing), so they attack from r+1
    -- if by_color=="b", black pawns move "downward" (r increasing), so they attack from r-1
    local pr = r - pawn_dr
    for _, dc in ipairs({-1, 1}) do
        local pc = c + dc
        if inBoard(pr, pc) and sq[pr][pc] == opp_pawn then return true end
    end

    -- Knight attacks
    local kdrs = {-2,-2,-1,-1,1,1,2,2}
    local kdcs = {-1,1,-2,2,-2,2,-1,1}
    for i = 1, 8 do
        local kr2, kc2 = r + kdrs[i], c + kdcs[i]
        if inBoard(kr2, kc2) and sq[kr2][kc2] == opp_knight then return true end
    end

    -- Rook / Queen (orthogonal rays)
    local orth = {{-1,0},{1,0},{0,-1},{0,1}}
    for _, d in ipairs(orth) do
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
    local diag = {{-1,-1},{-1,1},{1,-1},{1,1}}
    for _, d in ipairs(diag) do
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

function ChessBoard:_genPseudoMoves(color)
    local moves = {}
    local sq    = self.sq
    local ep    = self.ep
    local castle = self.castle

    local function addMove(fr, fc, tr, tc, special, promo_piece)
        moves[#moves + 1] = {
            fr = fr, fc = fc, tr = tr, tc = tc,
            capture = sq[tr][tc] ~= 0,
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
                        local promo_q = (color == "w") and 5 or 11
                        local promo_r2 = (color == "w") and 2 or 8
                        local promo_b = (color == "w") and 4 or 10
                        local promo_n = (color == "w") and 3 or 9
                        for _, pp in ipairs({promo_q, promo_r2, promo_b, promo_n}) do
                            moves[#moves+1] = { fr=r, fc=c, tr=nr, tc=c, capture=false,
                                special="promo", promo_piece=pp }
                        end
                    else
                        addMove(r, c, nr, c)
                        -- Forward 2 from start
                        if r == start_r and sq[r + dr*2][c] == 0 then
                            addMove(r, c, r + dr*2, c)
                        end
                    end
                end

                -- Diagonal captures
                for _, dc in ipairs({-1, 1}) do
                    local nr2, nc2 = r + dr, c + dc
                    if inBoard(nr2, nc2) then
                        local target = sq[nr2][nc2]
                        if target ~= 0 and pieceColor(target) ~= color then
                            if nr2 == promo_r then
                                local promo_q = (color == "w") and 5 or 11
                                local promo_r2 = (color == "w") and 2 or 8
                                local promo_b = (color == "w") and 4 or 10
                                local promo_n = (color == "w") and 3 or 9
                                for _, pp in ipairs({promo_q, promo_r2, promo_b, promo_n}) do
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
                local kdrs2 = {-2,-2,-1,-1,1,1,2,2}
                local kdcs2 = {-1,1,-2,2,-2,2,-1,1}
                for i = 1, 8 do
                    local nr, nc = r + kdrs2[i], c + kdcs2[i]
                    if inBoard(nr, nc) then
                        local target = sq[nr][nc]
                        if target == 0 or pieceColor(target) ~= color then
                            addMove(r, c, nr, nc)
                        end
                    end
                end

            -- Bishop
            elseif pt == 4 then
                local dirs = {{-1,-1},{-1,1},{1,-1},{1,1}}
                for _, d in ipairs(dirs) do
                    local rr, cc = r + d[1], c + d[2]
                    while inBoard(rr, cc) do
                        local target = sq[rr][cc]
                        if target ~= 0 then
                            if pieceColor(target) ~= color then addMove(r, c, rr, cc) end
                            break
                        end
                        addMove(r, c, rr, cc)
                        rr = rr + d[1]; cc = cc + d[2]
                    end
                end

            -- Rook
            elseif pt == 2 then
                local dirs = {{-1,0},{1,0},{0,-1},{0,1}}
                for _, d in ipairs(dirs) do
                    local rr, cc = r + d[1], c + d[2]
                    while inBoard(rr, cc) do
                        local target = sq[rr][cc]
                        if target ~= 0 then
                            if pieceColor(target) ~= color then addMove(r, c, rr, cc) end
                            break
                        end
                        addMove(r, c, rr, cc)
                        rr = rr + d[1]; cc = cc + d[2]
                    end
                end

            -- Queen
            elseif pt == 5 then
                local dirs = {{-1,-1},{-1,1},{1,-1},{1,1},{-1,0},{1,0},{0,-1},{0,1}}
                for _, d in ipairs(dirs) do
                    local rr, cc = r + d[1], c + d[2]
                    while inBoard(rr, cc) do
                        local target = sq[rr][cc]
                        if target ~= 0 then
                            if pieceColor(target) ~= color then addMove(r, c, rr, cc) end
                            break
                        end
                        addMove(r, c, rr, cc)
                        rr = rr + d[1]; cc = cc + d[2]
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
-- Returns a saved snapshot for undoing
-- ---------------------------------------------------------------------------

function ChessBoard:_applyMove(move)
    local sq = self.sq
    local saved = {
        sq_flat  = {},
        turn     = self.turn,
        castle   = { wK=self.castle.wK, wQ=self.castle.wQ,
                     bK=self.castle.bK, bQ=self.castle.bQ },
        ep       = self.ep,
        halfmove = self.halfmove,
    }
    -- Flatten board for fast snapshot
    for r = 1, 8 do
        for c = 1, 8 do
            saved.sq_flat[(r-1)*8+c] = sq[r][c]
        end
    end

    local fr, fc, tr, tc = move.fr, move.fc, move.tr, move.tc
    local piece = sq[fr][fc]

    -- En passant capture
    if move.special == "ep" then
        local cap_r = (self.turn == "w") and (tr + 1) or (tr - 1)
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
        if self.turn == "w" then self.castle.wK = false; self.castle.wQ = false
        else                     self.castle.bK = false; self.castle.bQ = false end
    elseif pt == 2 then
        if fr == 8 and fc == 1 then self.castle.wQ = false end
        if fr == 8 and fc == 8 then self.castle.wK = false end
        if fr == 1 and fc == 1 then self.castle.bQ = false end
        if fr == 1 and fc == 8 then self.castle.bK = false end
    end
    -- Also update if rook square is captured
    if tr == 8 and tc == 1 then self.castle.wQ = false end
    if tr == 8 and tc == 8 then self.castle.wK = false end
    if tr == 1 and tc == 1 then self.castle.bQ = false end
    if tr == 1 and tc == 8 then self.castle.bK = false end

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
    for r = 1, 8 do
        for c = 1, 8 do
            self.sq[r][c] = saved.sq_flat[(r-1)*8+c]
        end
    end
    self.turn     = saved.turn
    self.castle   = saved.castle
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
    elseif self.halfmove >= 100 then
        self.status = "draw"
        self.winner = nil
    else
        self.status = "playing"
        self.winner = nil
    end
    -- Invalidate move cache (it was used above, now stale)
    self._valid_moves_cache = nil
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

    -- Save snapshot for undo
    local snapshot = {
        sq_flat  = {},
        turn     = self.turn,
        castle   = { wK=self.castle.wK, wQ=self.castle.wQ,
                     bK=self.castle.bK, bQ=self.castle.bQ },
        ep       = self.ep,
        halfmove = self.halfmove,
        status   = self.status,
        winner   = self.winner,
        selected = self.selected,
    }
    for r = 1, 8 do
        for c = 1, 8 do
            snapshot.sq_flat[(r-1)*8+c] = self.sq[r][c]
        end
    end
    self._history[#self._history + 1] = snapshot

    -- Apply move
    self:_applyMove(found)

    self.selected = nil
    self._valid_moves_cache = nil
    self._selected_moves    = nil
    self.promo_pending      = nil

    self:_updateStatus()
    return true
end

-- ---------------------------------------------------------------------------
-- Undo
-- ---------------------------------------------------------------------------

function ChessBoard:undoMove()
    if #self._history == 0 then return false end
    local snap = table.remove(self._history)
    for r = 1, 8 do
        for c = 1, 8 do
            self.sq[r][c] = snap.sq_flat[(r-1)*8+c]
        end
    end
    self.turn     = snap.turn
    self.castle   = snap.castle
    self.ep       = snap.ep
    self.halfmove = snap.halfmove
    self.status   = snap.status
    self.winner   = snap.winner
    self.selected = nil
    self._valid_moves_cache = nil
    self._selected_moves    = nil
    self.promo_pending      = nil
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

function ChessBoard:serialize()
    local flat = {}
    for r = 1, 8 do
        for c = 1, 8 do
            flat[(r-1)*8+c] = self.sq[r][c]
        end
    end
    local hist = {}
    for i, snap in ipairs(self._history) do
        local h = {}
        h.sq_flat  = {}
        for k, v in pairs(snap.sq_flat) do h.sq_flat[k] = v end
        h.turn     = snap.turn
        h.castle   = { wK=snap.castle.wK, wQ=snap.castle.wQ,
                       bK=snap.castle.bK, bQ=snap.castle.bQ }
        h.ep       = snap.ep
        h.halfmove = snap.halfmove
        h.status   = snap.status
        h.winner   = snap.winner
        hist[i] = h
    end
    return {
        sq_flat  = flat,
        turn     = self.turn,
        castle   = { wK=self.castle.wK, wQ=self.castle.wQ,
                     bK=self.castle.bK, bQ=self.castle.bQ },
        ep       = self.ep,
        halfmove = self.halfmove,
        status   = self.status,
        winner   = self.winner,
        history  = hist,
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
    self.ep       = data.ep
    self.halfmove = data.halfmove or 0
    self.status   = data.status   or "playing"
    self.winner   = data.winner
    self._history = {}
    if type(data.history) == "table" then
        for _, h in ipairs(data.history) do
            local snap = {
                sq_flat  = {},
                turn     = h.turn,
                castle   = { wK=h.castle.wK, wQ=h.castle.wQ,
                             bK=h.castle.bK, bQ=h.castle.bQ },
                ep       = h.ep,
                halfmove = h.halfmove,
                status   = h.status,
                winner   = h.winner,
            }
            for k, v in pairs(h.sq_flat) do snap.sq_flat[k] = v end
            self._history[#self._history+1] = snap
        end
    end
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

function ChessBoard:_evaluate()
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

-- Move ordering: promotions > captures (MVV-LVA) > killers > quiet
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

local function sortMoves(moves, sq, killers)
    table.sort(moves, function(a, b)
        return moveScore(a, sq, killers) > moveScore(b, sq, killers)
    end)
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

-- Quiescence search: resolve captures/promotions before evaluating statically.
-- Prevents the horizon effect (e.g. "winning" a queen on move N then losing the
-- king on move N+1 being invisible at depth 0).
function ChessBoard:_quiescence(alpha, beta)
    local maximizing = (self.turn == "w")
    local stand_pat  = self:_evaluate()

    if maximizing then
        if stand_pat >= beta  then return beta  end
        if stand_pat > alpha  then alpha = stand_pat end
    else
        if stand_pat <= alpha then return alpha end
        if stand_pat < beta   then beta  = stand_pat end
    end

    local pseudo = self:_genPseudoMoves(self.turn)
    local caps = {}
    for _, m in ipairs(pseudo) do
        if (m.capture or m.special == "ep" or m.special == "promo")
                and self:_isMoveLegal(m) then
            caps[#caps + 1] = m
        end
    end
    sortMoves(caps, self.sq, nil)

    if maximizing then
        for _, m in ipairs(caps) do
            local saved = self:_applyMove(m)
            local score = self:_quiescence(alpha, beta)
            self:_undoMove(saved)
            if score >= beta then return beta  end
            if score > alpha then alpha = score end
        end
        return alpha
    else
        for _, m in ipairs(caps) do
            local saved = self:_applyMove(m)
            local score = self:_quiescence(alpha, beta)
            self:_undoMove(saved)
            if score <= alpha then return alpha end
            if score < beta   then beta  = score end
        end
        return beta
    end
end

function ChessBoard:_alphaBeta(depth, alpha, beta, maximizing)
    if depth == 0 then
        return self:_quiescence(alpha, beta), nil
    end

    local legal = self:getLegalMoves()
    if #legal == 0 then
        if self:isInCheck(self.turn) then
            return (maximizing and -30000 or 30000), nil
        end
        return 0, nil  -- stalemate
    end
    if self.halfmove >= 100 then return 0, nil end

    sortMoves(legal, self.sq, ai_killers[depth])

    local best_move = nil
    if maximizing then
        local best_val = -math.huge
        for _, m in ipairs(legal) do
            local saved = self:_applyMove(m)
            local val   = self:_alphaBeta(depth - 1, alpha, beta, false)
            self:_undoMove(saved)
            if val > best_val then best_val = val; best_move = m end
            if val > alpha    then alpha = val end
            if beta <= alpha  then storeKiller(depth, m); break end
        end
        return best_val, best_move
    else
        local best_val = math.huge
        for _, m in ipairs(legal) do
            local saved = self:_applyMove(m)
            local val   = self:_alphaBeta(depth - 1, alpha, beta, true)
            self:_undoMove(saved)
            if val < best_val then best_val = val; best_move = m end
            if val < beta     then beta = val end
            if beta <= alpha  then storeKiller(depth, m); break end
        end
        return best_val, best_move
    end
end

function ChessBoard:getAIMove(depth)
    depth = depth or 3
    if self.status ~= "playing" then return nil end

    ai_killers = {}  -- reset killer table for this search

    local maximizing = (self.turn == "w")
    local legal = self:getLegalMoves()
    if #legal == 0 then return nil end

    sortMoves(legal, self.sq, nil)

    -- Evaluate every root move; collect all moves tied at the best score so
    -- that equal lines are chosen randomly (adds variety without weakening play).
    local best_val   = maximizing and -math.huge or math.huge
    local best_moves = {}

    for _, m in ipairs(legal) do
        local saved = self:_applyMove(m)
        local val   = self:_alphaBeta(depth - 1, -math.huge, math.huge, not maximizing)
        self:_undoMove(saved)
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

    local best_move = best_moves[math.random(#best_moves)]
    if best_move and best_move.special == "promo" then
        best_move.promo_piece = (self.turn == "w") and ChessBoard.W_QUEEN or ChessBoard.B_QUEEN
    end
    return best_move
end

return ChessBoard
