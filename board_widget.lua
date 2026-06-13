-- ---------------------------------------------------------------------------
-- EchecsBoardWidget — renders the 8×8 chess board
-- Uses chess_pieces.lua for pixel-art piece rendering.
-- Supports flipping (black at bottom) via the `flipped` field.
-- ---------------------------------------------------------------------------

local Blitbuffer = require("ffi/blitbuffer")
local Font       = require("ui/font")
local Geom       = require("ui/geometry")
local RenderText = require("ui/rendertext")

local gwb            = require("grid_widget_base")
local GridWidgetBase = gwb.GridWidgetBase
local ChessPieces    = require("chess_pieces")

-- Square colors
local SQ_LIGHT   = Blitbuffer.COLOR_GRAY_E
local SQ_DARK    = Blitbuffer.COLOR_GRAY_9
local SQ_SEL     = Blitbuffer.COLOR_GRAY_C
local SQ_LASTMOV = Blitbuffer.COLOR_GRAY_B
local DOT_COLOR  = Blitbuffer.COLOR_GRAY_3

-- ---------------------------------------------------------------------------
-- EchecsBoardWidget
-- ---------------------------------------------------------------------------

local EchecsBoardWidget = GridWidgetBase:extend{
    board        = nil,
    size_ratio   = 0.80,
    onCellAction = nil,
    cols         = 8,
    rows         = 8,
    -- last_move: {fr,fc,tr,tc} or nil — set by screen after each move
    last_move    = nil,
    -- flipped: true → black's perspective (rank 1 at top)
    flipped      = false,
}

function EchecsBoardWidget:init()
    GridWidgetBase.init(self)
    local cell_min   = math.min(self.cell_w, self.cell_h)
    local label_size = math.max(6, math.floor(cell_min * 0.22))
    self.label_face  = Font:getFace("smallinfofont", label_size)
end

function EchecsBoardWidget:onCellTap(v_row, v_col)
    -- Translate visual cell to board coordinates
    local br = self.flipped and (9 - v_row) or v_row
    local bc = self.flipped and (9 - v_col) or v_col
    if self.onCellAction then self.onCellAction(br, bc) end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

function EchecsBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.size, h = self.size }

    local board  = self.board
    local sq     = board and board.sq
    if not sq then return end

    local cw     = self.cell_w
    local ch     = self.cell_h
    local flip   = self.flipped

    -- Selected square (in board coords)
    local sel_r, sel_c
    if board.selected then
        sel_r = board.selected.r
        sel_c = board.selected.c
    end

    -- Valid targets for selected piece
    local valid_targets = {}
    if sel_r then
        local moves = board:getMovesForSquare(sel_r, sel_c)
        for _, m in ipairs(moves) do
            valid_targets[m.tr * 8 + m.tc] = true
        end
    end

    -- Last move squares
    local lm         = self.last_move
    local lm_key_fr  = lm and (lm.fr * 8 + lm.fc) or nil
    local lm_key_to  = lm and (lm.tr * 8 + lm.tc) or nil

    for v_row = 1, 8 do
        for v_col = 1, 8 do
            -- Board coordinates for this visual cell
            local br = flip and (9 - v_row) or v_row
            local bc = flip and (9 - v_col) or v_col

            local px  = x + math.floor((v_col - 1) * cw)
            local py  = y + math.floor((v_row - 1) * ch)
            local pcw = math.ceil(cw)
            local pch = math.ceil(ch)

            -- Background colour
            local is_light = ((br + bc) % 2 == 0)
            local key       = br * 8 + bc
            local bg
            if sel_r and br == sel_r and bc == sel_c then
                bg = SQ_SEL
            elseif lm and (key == lm_key_fr or key == lm_key_to) then
                bg = SQ_LASTMOV
            elseif is_light then
                bg = SQ_LIGHT
            else
                bg = SQ_DARK
            end
            bb:paintRect(px, py, pcw, pch, bg)

            -- Valid-move dot
            if valid_targets[key] then
                local dot = math.max(3, math.floor(math.min(pcw, pch) * 0.20))
                bb:paintRect(px + math.floor((pcw - dot) / 2),
                             py + math.floor((pch - dot) / 2),
                             dot, dot, DOT_COLOR)
            end

            -- Piece
            local piece = sq[br][bc]
            if piece ~= 0 then
                ChessPieces.drawPiece(bb, px, py, pcw, pch, piece)
            end
        end
    end

    -- Board border
    local S = self.size
    bb:paintRect(x,       y,       S, 1, Blitbuffer.COLOR_BLACK)
    bb:paintRect(x,       y+S-1,   S, 1, Blitbuffer.COLOR_BLACK)
    bb:paintRect(x,       y,       1, S, Blitbuffer.COLOR_BLACK)
    bb:paintRect(x+S-1,   y,       1, S, Blitbuffer.COLOR_BLACK)

    -- Interior grid lines
    for i = 1, 7 do
        bb:paintRect(x + math.floor(i * cw), y,  1, S, Blitbuffer.COLOR_GRAY_9)
        bb:paintRect(x,  y + math.floor(i * ch), S, 1, Blitbuffer.COLOR_GRAY_9)
    end

    -- Rank / file labels
    local file_letters = {"a","b","c","d","e","f","g","h"}
    local label_face   = self.label_face
    for i = 1, 8 do
        -- Rank number (left edge of each row)
        local board_row  = flip and i or (9 - i)
        local rank_label = tostring(board_row)
        local lx  = x + math.floor((i - 1) * cw) + 1
        local ly  = y + math.floor((i - 1) * ch) + 1
        local m1  = RenderText:sizeUtf8Text(0, 20, label_face, rank_label, true, false)
        RenderText:renderUtf8Text(bb, lx, ly + (m1.y_bottom or 0), label_face, rank_label,
            true, false, Blitbuffer.COLOR_GRAY_5)

        -- File letter (bottom edge of each column)
        local board_col  = flip and (9 - i) or i
        local file_label = file_letters[board_col] or ""
        local lx2 = x + math.floor((i - 1) * cw) + math.floor(cw / 2)
        local m2  = RenderText:sizeUtf8Text(0, 20, label_face, file_label, true, false)
        RenderText:renderUtf8Text(bb, lx2 - math.floor(m2.x / 2),
            y + S - 2, label_face, file_label, true, false, Blitbuffer.COLOR_GRAY_5)
    end
end

return EchecsBoardWidget
