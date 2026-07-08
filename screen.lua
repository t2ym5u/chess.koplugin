-- ---------------------------------------------------------------------------
-- EchecsScreen — game screen for the chess plugin
-- ---------------------------------------------------------------------------

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")

local MenuHelper       = require("menu_helper")
local ScreenBase       = require("screen_base")

local ChessBoard       = lrequire("board")
local EchecsBoardWidget = lrequire("board_widget")

local DeviceScreen = Device.screen

-- ---------------------------------------------------------------------------
-- EchecsScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Chess — Rules

Standard chess between two players.

Pieces move as follows:
• King — one square in any direction; cannot move into check.
• Queen — any number of squares in any direction.
• Rook — any number of squares horizontally or vertically.
• Bishop — any number of squares diagonally.
• Knight — L-shape (2 squares then 1 square); the only piece that can jump over others.
• Pawn — moves forward one square (two on its first move); captures diagonally.

Special moves: castling, en passant, pawn promotion.
Win by delivering checkmate — putting the opponent's king in check with no escape.
]])

local GAME_RULES_FR = [[
Échecs — Règles

Partie d'échecs standard entre deux joueurs.

Chaque pièce se déplace ainsi :
• Roi — une case dans n'importe quelle direction ; ne peut pas se mettre en échec.
• Dame — autant de cases que souhaité dans n'importe quelle direction.
• Tour — autant de cases que souhaité horizontalement ou verticalement.
• Fou — autant de cases que souhaité en diagonale.
• Cavalier — en forme de "L" (2 cases puis 1 case) ; la seule pièce pouvant sauter.
• Pion — avance d'une case (deux lors du premier déplacement) ; capture en diagonale.

Coups spéciaux : roque, prise en passant, promotion du pion.
Gagnez en mettant le roi adverse en échec et mat.
]]

local EchecsScreen = ScreenBase:extend{}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function EchecsScreen:init()
    local state = self.plugin:loadState()
    self.board = ChessBoard:new()
    if not self.board:load(state) then
        self.board:reset()
    end
    -- Flip board when human plays black (so white is always at the bottom by default)
    local pc = self.plugin:getSetting("player_color", "w")
    self._flipped = (self.plugin:getSetting("players", 1) == 1 and pc == "b")
    ScreenBase.init(self)
    if self.board.status == "playing" and self:_isAITurn() then
        self:triggerAI()
    end
end

function EchecsScreen:serializeState()
    return self.board:serialize()
end

function EchecsScreen:_isAITurn()
    local players = self.plugin:getSetting("players", 1)
    if players ~= 1 then return false end
    local pc = self.plugin:getSetting("player_color", "w")
    -- AI plays the opposite color of the human
    local ai_color = (pc == "w") and "b" or "w"
    return self.board.turn == ai_color
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function EchecsScreen:buildLayout()
    local board = self.board

    self.board_widget = EchecsBoardWidget:new{
        board        = board,
        flipped      = self._flipped or false,
        onCellAction = function(r, c) self:onCellTap(r, c) end,
    }

    local is_landscape = self:isLandscape()
    local sw = DeviceScreen:getWidth()

    local board_frame = FrameContainer:new{
        padding = Size.padding.default,
        margin  = Size.margin.default,
        self.board_widget,
    }

    local bw_size      = self.board_widget.size
        + (Size.padding.default + Size.margin.default) * 2
    local buttons_w    = is_landscape
        and math.max(sw - bw_size - Size.span.horizontal_default, 120)
        or  math.floor(sw * 0.94)

    -- Action buttons row
    local action_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = buttons_w,
        buttons = {
            {
                { text = _("Nouveau"),    callback = function() self:onNewGame() end },
                { text = _("Joueurs"),    callback = function() self:openPlayersMenu() end },
                { id = "diff_btn",
                  text = self:_diffLabel(),
                  callback = function() self:openDifficultyMenu() end },
                { text = _("Annuler"),    callback = function() self:onUndo() end },
                { text = _("Retourner"), callback = function() self:onFlipBoard() end },
                self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
                self:makeCloseButtonConfig(),
            },
        },
    }

    self.diff_btn = action_buttons:getButtonById("diff_btn")

    if is_landscape then
        local right_panel = VerticalGroup:new{
            align = "center",
            action_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
        }
        self.layout = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right_panel,
        }
    else
        local content = VerticalGroup:new{
            align = "center",
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
        }
        self:buildPortraitLayout(action_buttons, content, nil)
    end

    self[1] = self.layout
    self:updateStatus()
end

function EchecsScreen:_diffLabel()
    local diff = self.plugin:getSetting("difficulty", "medium")
    return MenuHelper.DIFFICULTY_LABELS[diff] or diff
end

-- ---------------------------------------------------------------------------
-- Cell tap handler
-- ---------------------------------------------------------------------------

function EchecsScreen:onCellTap(r, c)
    if self.board.status ~= "playing" then return end
    -- In 1-player mode, block taps when it's the AI's turn
    if self:_isAITurn() then return end

    local result = self.board:tapCell(r, c)

    if result == "promo_needed" then
        self:showPromoDialog()
        return
    end

    self.board_widget:refresh()
    self:updateStatus()

    if result == "move" then
        -- Propagate last move highlight to widget
        if self.board.last_move and self.board_widget then
            self.board_widget.last_move = self.board.last_move
        end
        self.plugin:saveState(self:serializeState())
        if self.board.status ~= "playing" then
            self:onGameEnd()
        elseif self:_isAITurn() then
            self:triggerAI()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Promotion dialog
-- ---------------------------------------------------------------------------

function EchecsScreen:showPromoDialog()
    local board   = self.board
    local color   = board.promo_pending
        and (board.turn == "w" and "w" or "b")
        or  board.turn

    local W_QUEEN  = ChessBoard.W_QUEEN;  local B_QUEEN  = ChessBoard.B_QUEEN
    local W_ROOK   = ChessBoard.W_ROOK;   local B_ROOK   = ChessBoard.B_ROOK
    local W_BISHOP = ChessBoard.W_BISHOP; local B_BISHOP = ChessBoard.B_BISHOP
    local W_KNIGHT = ChessBoard.W_KNIGHT; local B_KNIGHT = ChessBoard.B_KNIGHT

    local pieces = (color == "w")
        and { W_QUEEN, W_ROOK, W_BISHOP, W_KNIGHT }
        or  { B_QUEEN, B_ROOK, B_BISHOP, B_KNIGHT }
    local labels = { _("Dame"), _("Tour"), _("Fou"), _("Cavalier") }

    local buttons = {}
    for i, pv in ipairs(pieces) do
        local piece_val = pv
        local lbl       = labels[i]
        buttons[#buttons+1] = {
            text     = lbl,
            callback = function()
                UIManager:close(self._promo_dialog)
                self._promo_dialog = nil
                board:finishPromo(piece_val)
                self.board_widget:refresh()
                self:updateStatus()
                self.plugin:saveState(self:serializeState())
                if board.status ~= "playing" then
                    self:onGameEnd()
                elseif self:_isAITurn() then
                    self:triggerAI()
                end
            end,
        }
    end

    local ButtonDialog = require("ui/widget/buttondialog")
    self._promo_dialog = ButtonDialog:new{
        title   = _("Promotion — choisissez la pièce :"),
        buttons = { buttons },
    }
    UIManager:show(self._promo_dialog)
end

-- ---------------------------------------------------------------------------
-- Game end handler
-- ---------------------------------------------------------------------------

function EchecsScreen:onGameEnd()
    local InfoMessage = require("ui/widget/infomessage")
    local msg
    local st = self.board.status
    if st == "checkmate" then
        local winner = (self.board.winner == "w") and _("Blancs") or _("Noirs")
        msg = winner .. " " .. _("gagnent par mat !")
    elseif st == "stalemate" then
        msg = _("Pat — partie nulle.")
    elseif st == "draw" then
        msg = _("Nulle (règle des 50 coups).")
    else
        return
    end
    UIManager:scheduleIn(0.3, function()
        UIManager:show(InfoMessage:new{ text = msg, timeout = 5 })
    end)
end

-- ---------------------------------------------------------------------------
-- New game
-- ---------------------------------------------------------------------------

function EchecsScreen:onNewGame()
    self.board:reset()
    self.plugin:saveState(self:serializeState())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    -- If AI plays first
    if self:_isAITurn() then
        self:triggerAI()
    end
end

-- ---------------------------------------------------------------------------
-- Flip board
-- ---------------------------------------------------------------------------

function EchecsScreen:onFlipBoard()
    self._flipped = not (self._flipped or false)
    if self.board_widget then
        self.board_widget.flipped = self._flipped
        self.board_widget:refresh()
    end
end

-- ---------------------------------------------------------------------------
-- Undo
-- ---------------------------------------------------------------------------

function EchecsScreen:onUndo()
    local players = self.plugin:getSetting("players", 1)
    -- In 1-player mode, undo twice (undo AI move and human move)
    if players == 1 then
        self.board:undoMove()  -- undo AI move (may be no-op if AI hasn't moved)
        self.board:undoMove()  -- undo human move
    else
        self.board:undoMove()
    end
    self.plugin:saveState(self:serializeState())
    self.board_widget:refresh()
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- AI trigger
-- ---------------------------------------------------------------------------

function EchecsScreen:triggerAI()
    if self.board.status ~= "playing" then return end
    self:updateStatus(_("L'IA réfléchit..."))
    local diff  = self.plugin:getSetting("difficulty", "medium")
    local depth = (diff == "easy") and 1 or (diff == "hard") and 3 or 2
    UIManager:scheduleIn(0.1, function()
        local move = self.board:getAIMove(depth)
        if move then
            self.board:makeMove(move.fr, move.fc, move.tr, move.tc, move.promo_piece)
            if self.board_widget then
                self.board_widget.last_move = move
            end
        end
        if self.board_widget then self.board_widget:refresh() end
        self.plugin:saveState(self:serializeState())
        self:updateStatus()
        if self.board.status ~= "playing" then
            self:onGameEnd()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Players menu
-- ---------------------------------------------------------------------------

function EchecsScreen:openPlayersMenu()
    local players = self.plugin:getSetting("players", 1)
    MenuHelper.openPickerMenu{
        title      = _("Nombre de joueurs"),
        items      = {
            { id = 1, text = _("1 joueur (contre l'IA)") },
            { id = 2, text = _("2 joueurs") },
        },
        current_id = players,
        on_select  = function(id)
            self.plugin:saveSetting("players", id)
            if id == 1 then
                self:openColorMenu()
            else
                self:updateStatus()
                UIManager:setDirty(self, function() return "ui", self.dimen end)
            end
        end,
        parent = self,
    }
end

function EchecsScreen:openColorMenu()
    local pc = self.plugin:getSetting("player_color", "w")
    MenuHelper.openPickerMenu{
        title      = _("Jouez avec"),
        items      = {
            { id = "w", text = _("Blancs") },
            { id = "b", text = _("Noirs") },
        },
        current_id = pc,
        on_select  = function(id)
            self.plugin:saveSetting("player_color", id)
            -- Auto-flip board: black player should see black at bottom
            self._flipped = (id == "b")
            self:updateStatus()
            UIManager:setDirty(self, function() return "ui", self.dimen end)
            if self:_isAITurn() and self.board.status == "playing" then
                self:triggerAI()
            end
        end,
        parent = self,
    }
end

-- ---------------------------------------------------------------------------
-- Difficulty menu
-- ---------------------------------------------------------------------------

function EchecsScreen:openDifficultyMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "medium"),
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            if self.diff_btn then
                local lbl = MenuHelper.DIFFICULTY_LABELS[id] or id
                self.diff_btn:setText(lbl, self.diff_btn.width)
            end
            self:updateStatus()
            UIManager:setDirty(self, function() return "ui", self.dimen end)
        end,
        parent = self,
    }
end

-- ---------------------------------------------------------------------------
-- Status bar
-- ---------------------------------------------------------------------------

function EchecsScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    else
        local board = self.board
        if board.status == "checkmate" then
            local winner = (board.winner == "w") and _("Blancs") or _("Noirs")
            status = winner .. " " .. _("gagnent par mat !")
        elseif board.status == "stalemate" then
            status = _("Pat — partie nulle.")
        elseif board.status == "draw" then
            status = _("Nulle (règle des 50 coups).")
        else
            local turn = (board.turn == "w") and _("Blancs") or _("Noirs")
            local in_check = board:isInCheck(board.turn)
            if in_check then
                status = turn .. " — " .. _("ÉCHEC !")
            else
                status = turn .. " " .. _("jouent.")
            end
            local players = self.plugin:getSetting("players", 1)
            if players == 1 then
                local pc = self.plugin:getSetting("player_color", "w")
                local ai_label = (pc == "w") and _("(IA=Noirs)") or _("(IA=Blancs)")
                local diff = self.plugin:getSetting("difficulty", "medium")
                local diff_label = MenuHelper.DIFFICULTY_LABELS[diff] or diff
                status = status .. "  ·  " .. diff_label .. " " .. ai_label
            end
        end
    end
    ScreenBase.updateStatus(self, status)
end

return EchecsScreen
