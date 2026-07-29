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
    -- flipped: true → black's perspective (rank 1 at top)
    flipped      = false,
}

function EchecsBoardWidget:init()
    GridWidgetBase.init(self)

    -- Rank/file coordinate labels get their own margin outside the 8x8
    -- grid, instead of being overlaid on top of the board's own cells
    -- where they collide with piece art. The margin is reserved on the
    -- left (rank numbers) and at the bottom (file letters); the playable
    -- grid shrinks to fit the remaining square so the widget's overall
    -- footprint (self.size, used by callers for outer layout sizing)
    -- is unchanged.
    local approx_cell = self.size / 8
    local label_size   = math.max(6, math.floor(approx_cell * 0.22))
    self.label_face    = Font:getFace("smallinfofont", label_size)

    local sample = RenderText:sizeUtf8Text(0, 200, self.label_face, "8", true, false)
    self.label_margin = sample.x + math.floor(approx_cell * 0.15)

    self.grid_size = self.size - self.label_margin
    self.cell_w    = self.grid_size / 8
    self.cell_h    = self.grid_size / 8
end

function EchecsBoardWidget:onCellTap(v_row, v_col)
    -- Translate visual cell to board coordinates
    local br = self.flipped and (9 - v_row) or v_row
    local bc = self.flipped and (9 - v_col) or v_col
    if self.onCellAction then self.onCellAction(br, bc) end
end

-- Override: the tappable grid is offset by label_margin from the widget's
-- own origin (self.paint_rect covers the full widget, margin included, so
-- that refresh()'s dirty region still repaints the labels too).
function EchecsBoardWidget:getCellFromPoint(px, py)
    local rect = self.paint_rect
    if not rect then return nil end
    local gx = rect.x + self.label_margin
    local gy = rect.y
    local local_x = px - gx
    local local_y = py - gy
    if local_x < 0 or local_y < 0 or local_x > self.grid_size or local_y > self.grid_size then
        return nil
    end
    local col = math.min(8, math.floor(local_x / self.cell_w) + 1)
    local row = math.min(8, math.floor(local_y / self.cell_h) + 1)
    if row < 1 or col < 1 then return nil end
    return row, col
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

function EchecsBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.size, h = self.size }

    local board  = self.board
    local sq     = board and board.sq
    if not sq then return end

    local margin = self.label_margin
    local gx, gy = x + margin, y
    local gs     = self.grid_size
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
    local lm         = board.last_move
    local lm_key_fr  = lm and (lm.fr * 8 + lm.fc) or nil
    local lm_key_to  = lm and (lm.tr * 8 + lm.tc) or nil

    for v_row = 1, 8 do
        for v_col = 1, 8 do
            -- Board coordinates for this visual cell
            local br = flip and (9 - v_row) or v_row
            local bc = flip and (9 - v_col) or v_col

            local px  = gx + math.floor((v_col - 1) * cw)
            local py  = gy + math.floor((v_row - 1) * ch)
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
    bb:paintRect(gx,      gy,      gs, 1, Blitbuffer.COLOR_BLACK)
    bb:paintRect(gx,      gy+gs-1, gs, 1, Blitbuffer.COLOR_BLACK)
    bb:paintRect(gx,      gy,      1, gs, Blitbuffer.COLOR_BLACK)
    bb:paintRect(gx+gs-1, gy,      1, gs, Blitbuffer.COLOR_BLACK)

    -- Interior grid lines
    for i = 1, 7 do
        bb:paintRect(gx + math.floor(i * cw), gy, 1, gs, Blitbuffer.COLOR_GRAY_9)
        bb:paintRect(gx, gy + math.floor(i * ch), gs, 1, Blitbuffer.COLOR_GRAY_9)
    end

    -- Rank / file labels, drawn outside the grid in the reserved margin
    local file_letters = {"a","b","c","d","e","f","g","h"}
    local label_face   = self.label_face
    for i = 1, 8 do
        -- Rank number: left margin, vertically centered on row i
        local board_row  = flip and i or (9 - i)
        local rank_label = tostring(board_row)
        local row_top = gy + math.floor((i - 1) * ch)
        local m1      = RenderText:sizeUtf8Text(0, margin, label_face, rank_label, true, false)
        local base1   = row_top + math.floor((ch + m1.y_top - m1.y_bottom) / 2)
        local lx1     = x + math.floor((margin - m1.x) / 2)
        RenderText:renderUtf8Text(bb, lx1, base1, label_face, rank_label,
            true, false, Blitbuffer.COLOR_GRAY_5)

        -- File letter: bottom margin, horizontally centered on column i
        local board_col  = flip and (9 - i) or i
        local file_label = file_letters[board_col] or ""
        local col_left = gx + math.floor((i - 1) * cw)
        local m2       = RenderText:sizeUtf8Text(0, margin, label_face, file_label, true, false)
        local lx2      = col_left + math.floor((cw - m2.x) / 2)
        local base2    = gy + gs + math.floor((margin + m2.y_top - m2.y_bottom) / 2)
        RenderText:renderUtf8Text(bb, lx2, base2, label_face, file_label,
            true, false, Blitbuffer.COLOR_GRAY_5)
    end
end

return EchecsBoardWidget
