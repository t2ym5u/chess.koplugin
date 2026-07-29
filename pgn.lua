-- ---------------------------------------------------------------------------
-- pgn.lua — SAN move notation + PGN import/export for chess.koplugin
--
-- Deliberately has no dependency on board.lua (avoids a circular require,
-- since board.lua requires this module to build its SAN move log). Operates
-- on any object that duck-types a ChessBoard instance: `.sq`, `.turn`,
-- `:getLegalMoves()`, `:isInCheck(color)`, `:_applyMove(move)`, `:_undoMove(saved)`.
--
-- Coordinate system matches board.lua: r=1 is the black back rank (rank 8),
-- r=8 is the white back rank (rank 1), c=1 is the a-file.
-- ---------------------------------------------------------------------------

local M = {}

-- ---------------------------------------------------------------------------
-- Square helpers
-- ---------------------------------------------------------------------------

local FILE_LETTERS = "abcdefgh"

local function fileLetter(c) return FILE_LETTERS:sub(c, c) end
local function fileIndex(ch) return FILE_LETTERS:find(ch, 1, true) end

function M.squareName(r, c)
    return fileLetter(c) .. tostring(9 - r)
end

function M.parseSquare(str)
    local file, rank = str:match("^(%a)(%d)$")
    if not file then return nil end
    local c = fileIndex(file:lower())
    if not c then return nil end
    return 9 - tonumber(rank), c
end

-- ---------------------------------------------------------------------------
-- Piece-encoding helpers (mirrors board.lua's private pieceType()/isWhite())
-- ---------------------------------------------------------------------------

local function pieceTypeOf(v)
    if v == 0 then return 0 end
    return ((v - 1) % 6) + 1
end

local function isWhitePieceOf(v)
    return v >= 1 and v <= 6
end

local PIECE_LETTER    = { [2] = "R", [3] = "N", [4] = "B", [5] = "Q", [6] = "K" }
local LETTER_TO_PTYPE = { R = 2, N = 3, B = 4, Q = 5, K = 6 }

-- ---------------------------------------------------------------------------
-- SAN generation
-- ---------------------------------------------------------------------------

-- Disambiguation string for a non-pawn, non-king move: "" unless another
-- legal move of the same piece type/colour can also reach the destination.
local function disambiguation(board, move, pt, is_white)
    local file_conflict, rank_conflict, any_conflict = false, false, false
    for _, m in ipairs(board:getLegalMoves()) do
        if not (m.fr == move.fr and m.fc == move.fc) and m.tr == move.tr and m.tc == move.tc then
            local p2 = board.sq[m.fr][m.fc]
            if pieceTypeOf(p2) == pt and isWhitePieceOf(p2) == is_white then
                any_conflict = true
                if m.fc == move.fc then file_conflict = true end
                if m.fr == move.fr then rank_conflict = true end
            end
        end
    end
    if not any_conflict then return "" end
    if not file_conflict then return fileLetter(move.fc) end
    if not rank_conflict then return tostring(9 - move.fr) end
    return M.squareName(move.fr, move.fc)
end

-- Builds the SAN string for `move`, which must not have been applied to
-- `board` yet (disambiguation is computed against the pre-move position).
-- Temporarily applies/undoes the move internally (via the engine's own
-- apply/undo, same as legality checking) to detect a trailing "+"/"#" —
-- `board` is left exactly as it was found.
function M.toSAN(board, move)
    local san

    if move.special == "castle_k" then
        san = "O-O"
    elseif move.special == "castle_q" then
        san = "O-O-O"
    else
        local piece    = board.sq[move.fr][move.fc]
        local pt       = pieceTypeOf(piece)
        local is_white = isWhitePieceOf(piece)
        local is_capture = move.capture or move.special == "ep"
        local dest = M.squareName(move.tr, move.tc)

        if pt == 1 then
            san = is_capture and (fileLetter(move.fc) .. "x" .. dest) or dest
            if move.special == "promo" then
                san = san .. "=" .. (PIECE_LETTER[pieceTypeOf(move.promo_piece)] or "Q")
            end
        else
            local letter = PIECE_LETTER[pt] or "?"
            local dis    = disambiguation(board, move, pt, is_white)
            san = letter .. dis .. (is_capture and "x" or "") .. dest
        end
    end

    local saved = board:_applyMove(move)
    if board:isInCheck(board.turn) then
        san = san .. (#board:getLegalMoves() == 0 and "#" or "+")
    end
    board:_undoMove(saved)

    return san
end

-- ---------------------------------------------------------------------------
-- SAN parsing — find the legal move (on `board`, in its current position)
-- that a SAN token refers to. Returns nil if no legal move matches.
-- ---------------------------------------------------------------------------

function M.findMoveForSAN(board, san)
    local clean = san:gsub("[+#!?]+$", "")

    if clean == "O-O" or clean == "0-0" then
        for _, m in ipairs(board:getLegalMoves()) do
            if m.special == "castle_k" then return m end
        end
        return nil
    end
    if clean == "O-O-O" or clean == "0-0-0" then
        for _, m in ipairs(board:getLegalMoves()) do
            if m.special == "castle_q" then return m end
        end
        return nil
    end

    local body, promo_letter = clean:match("^(.-)=(%a)$")
    body = body or clean

    local piece_letter, rest = body:match("^([RNBQK])(.*)$")
    rest = rest or body
    rest = rest:gsub("x", "")
    if #rest < 2 then return nil end

    local dest      = rest:sub(-2)
    local dis       = rest:sub(1, -3)
    local dest_r, dest_c = M.parseSquare(dest)
    if not dest_r then return nil end

    local dis_file, dis_rank
    for ch in dis:gmatch(".") do
        if ch:match("%a") then dis_file = fileIndex(ch)
        elseif ch:match("%d") then dis_rank = 9 - tonumber(ch) end
    end

    local wanted_pt = piece_letter and LETTER_TO_PTYPE[piece_letter] or 1
    local wanted_promo_pt = promo_letter and LETTER_TO_PTYPE[promo_letter]

    for _, m in ipairs(board:getLegalMoves()) do
        if m.tr == dest_r and m.tc == dest_c
                and (not dis_file or m.fc == dis_file)
                and (not dis_rank or m.fr == dis_rank) then
            local p = board.sq[m.fr][m.fc]
            if pieceTypeOf(p) == wanted_pt then
                if wanted_promo_pt then
                    if m.special == "promo" and pieceTypeOf(m.promo_piece) == wanted_promo_pt then
                        return m
                    end
                elseif m.special ~= "promo" then
                    return m
                end
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- PGN text (headers + movetext) build/parse
-- ---------------------------------------------------------------------------

local HEADER_ORDER = { "Event", "Site", "Date", "Round", "White", "Black", "Result" }

function M.buildPGN(headers, sans)
    headers = headers or {}
    local lines, seen = {}, {}
    for _, key in ipairs(HEADER_ORDER) do
        if headers[key] then
            lines[#lines + 1] = string.format('[%s "%s"]', key, headers[key])
            seen[key] = true
        end
    end
    for k, v in pairs(headers) do
        if not seen[k] then lines[#lines + 1] = string.format('[%s "%s"]', k, v) end
    end

    local movetext = {}
    for i, san in ipairs(sans) do
        if i % 2 == 1 then
            movetext[#movetext + 1] = tostring(math.floor((i - 1) / 2) + 1) .. "."
        end
        movetext[#movetext + 1] = san
    end
    movetext[#movetext + 1] = headers.Result or "*"

    return table.concat(lines, "\n") .. "\n\n" .. table.concat(movetext, " ") .. "\n"
end

local RESULT_TOKENS = { ["*"] = true, ["1-0"] = true, ["0-1"] = true, ["1/2-1/2"] = true }

function M.parsePGN(text)
    local headers = {}
    for tag, value in text:gmatch('%[(%a+)%s+"(.-)"%]') do
        headers[tag] = value
    end

    local movetext = text:gsub("%[.-%]", "")
    movetext = movetext:gsub("{.-}", "")
    movetext = movetext:gsub("%$%d+", "")
    movetext = movetext:gsub("%d+%.%.?%.?", "")

    local sans = {}
    for token in movetext:gmatch("%S+") do
        if not RESULT_TOKENS[token] then sans[#sans + 1] = token end
    end
    return headers, sans
end

return M
