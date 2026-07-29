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
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")

local MenuHelper       = require("menu_helper")
local ScreenBase       = require("screen_base")

local ChessBoard       = lrequire("board")
local EchecsBoardWidget = lrequire("board_widget")
local PGN              = lrequire("pgn")
local ChessClock       = lrequire("chess_clock")
local EngineHome       = lrequire("engine_home")
local EngineUCI        = lrequire("engine_uci")

local UCI_BINARY_PATH = _dir .. "bin/stockfish"

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
    -- Backward compatible with old saves (the board data directly, no wrapper).
    local board_data = state and (state.board or (state.sq_flat and state)) or nil

    self.board = ChessBoard:new()
    if not self.board:load(board_data) then
        self.board:reset()
    end
    self._time_forfeit = state and state.time_forfeit or nil

    if self.plugin:getSetting("clock_enabled", false) then
        self:_createClock()
        if state and state.clock then self.clock:load(state.clock) end
        self.clock.turn = self.board.turn
    end

    -- Flip board when human plays black (so white is always at the bottom by default)
    local pc = self.plugin:getSetting("player_color", "w")
    self._flipped = (self.plugin:getSetting("players", 1) == 1 and pc == "b")
    ScreenBase.init(self)

    if self.board.status == "playing" and not self._time_forfeit then
        if self.clock then self.clock:start() end
        if self:_isAITurn() then self:triggerAI() end
    end
end

function EchecsScreen:serializeState()
    return {
        board        = self.board:serialize(),
        clock        = self.clock and self.clock:serialize() or nil,
        time_forfeit = self._time_forfeit,
    }
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

    -- Title bar with Options menu
    local title_bar = self:buildTitleBar(_("Échecs"), function()
        local items = {
            { text = _("Nouveau"),      callback = function() self:onNewGame() end },
            { text = _("Joueurs"),      callback = function() self:openPlayersMenu() end },
            { text = self:_diffLabel(), callback = function() self:openDifficultyMenu() end },
            { text = _("Pendule"),      callback = function() self:openClockMenu() end },
            { text = _("Exporter PGN"), callback = function() self:onExportPGN() end },
            { text = _("Importer PGN"), callback = function() self:onImportPGN() end },
        }
        if EngineUCI.binaryAvailable(UCI_BINARY_PATH) then
            items[#items + 1] = { text = _("Moteur"), callback = function() self:openEngineMenu() end }
        end
        items[#items + 1] = self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR)
        return items
    end)

    -- Bottom button row: Undo | Redo | Flip
    local bottom_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = buttons_w,
        buttons = {{
            { text = _("Annuler"),   callback = function() self:onUndo() end },
            { text = _("Rejouer"),   callback = function() self:onRedo() end },
            { text = _("Retourner"), callback = function() self:onFlipBoard() end },
        }},
    }

    self.clock_text = nil
    local status_block = self.status_text
    if self.clock then
        self.clock_text = TextWidget:new{ text = "", face = Font:getFace("smallinfofont") }
        status_block = VerticalGroup:new{
            align = "center",
            self.status_text,
            VerticalSpan:new{ width = Size.padding.small },
            self.clock_text,
        }
        self:_updateClockDisplay()
    end

    if is_landscape then
        local right_panel = VerticalGroup:new{
            align = "center",
            status_block,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
        }
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right_panel,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        local content = VerticalGroup:new{
            align = "center",
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            status_block,
        }
        self:buildPortraitLayout(title_bar, content, bottom_buttons)
    end
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
        if self.clock then
            if self.board.status == "playing" then self.clock:switchPlayer() else self.clock:stop() end
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
                if self.clock then
                    if board.status == "playing" then self.clock:switchPlayer() else self.clock:stop() end
                end
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

local function drawReasonLabel(reason)
    if reason == "insufficient_material" then return _("matériel insuffisant") end
    if reason == "repetition"            then return _("répétition de position") end
    return _("règle des 50 coups")
end

function EchecsScreen:onGameEnd()
    if self.clock then self.clock:stop() end

    local InfoMessage = require("ui/widget/infomessage")
    local msg
    if self._time_forfeit then
        local winner = (self._time_forfeit == "w") and _("Noirs") or _("Blancs")
        msg = winner .. " " .. _("gagnent au temps !")
    else
        local st = self.board.status
        if st == "checkmate" then
            local winner = (self.board.winner == "w") and _("Blancs") or _("Noirs")
            msg = winner .. " " .. _("gagnent par mat !")
        elseif st == "stalemate" then
            msg = _("Pat — partie nulle.")
        elseif st == "draw" then
            msg = _("Nulle") .. " (" .. drawReasonLabel(self.board.draw_reason) .. ")."
        else
            return
        end
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
    self._time_forfeit = nil
    if self.clock then
        self.clock:reset()
        self.clock:start()
    end
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
    self:_getEngine():cancelPending()
    local players = self.plugin:getSetting("players", 1)
    -- In 1-player mode, undo twice (undo AI move and human move)
    if players == 1 then
        self.board:undoMove()  -- undo AI move (may be no-op if AI hasn't moved)
        self.board:undoMove()  -- undo human move
    else
        self.board:undoMove()
    end
    self._time_forfeit = nil
    if self.clock then
        self.clock:syncTurn(self.board.turn)
        if self.board.status ~= "playing" then self.clock:stop() end
    end
    self.plugin:saveState(self:serializeState())
    self.board_widget:refresh()
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Redo
-- ---------------------------------------------------------------------------

function EchecsScreen:onRedo()
    self:_getEngine():cancelPending()
    local players = self.plugin:getSetting("players", 1)
    -- In 1-player mode, redo twice (redo human move and AI move), symmetric to onUndo
    if players == 1 then
        self.board:redoMove()
        self.board:redoMove()
    else
        self.board:redoMove()
    end
    if self.clock then
        self.clock:syncTurn(self.board.turn)
        if self.board.status ~= "playing" then self.clock:stop() end
    end
    self.plugin:saveState(self:serializeState())
    self.board_widget:refresh()
    self:updateStatus()
    if self.board.status ~= "playing" then
        self:onGameEnd()
    end
end

-- ---------------------------------------------------------------------------
-- AI trigger
-- ---------------------------------------------------------------------------

-- Returns the engine to use for AI moves: the UCI engine only if the user
-- selected it AND it is actually spawned+handshaked; the home engine always
-- works as the fallback (see openEngineMenu/_activateUCIEngine for how the
-- UCI engine gets activated in the first place).
function EchecsScreen:_getEngine()
    if self.plugin:getSetting("engine", "home") == "uci"
            and self._uci_engine and self._uci_engine:isAvailable() then
        return self._uci_engine
    end
    if not self._home_engine then self._home_engine = EngineHome:new() end
    return self._home_engine
end

function EchecsScreen:triggerAI()
    if self.board.status ~= "playing" then return end
    self:updateStatus(_("L'IA réfléchit..."))
    local diff = self.plugin:getSetting("difficulty", "medium")
    self:_getEngine():requestMove(self.board, diff, function(move)
        if move then
            self.board:makeMove(move.fr, move.fc, move.tr, move.tc, move.promo_piece)
        end
        if self.clock then
            if self.board.status == "playing" then self.clock:switchPlayer() else self.clock:stop() end
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
-- Engine selection (home AI vs. optional Stockfish/UCI)
-- ---------------------------------------------------------------------------

function EchecsScreen:openEngineMenu()
    local current = self.plugin:getSetting("engine", "home")
    MenuHelper.openPickerMenu{
        title      = _("Moteur"),
        items      = {
            { id = "home", text = _("Maison") },
            { id = "uci",  text = _("Stockfish (UCI)") },
        },
        current_id = current,
        on_select  = function(id)
            if id == "uci" then
                self:_activateUCIEngine()
            else
                if self._uci_engine then self._uci_engine:stop() end
                self.plugin:saveSetting("engine", "home")
            end
        end,
        parent = self,
    }
end

function EchecsScreen:_activateUCIEngine()
    if not self._uci_engine then
        self._uci_engine = EngineUCI:new(UCI_BINARY_PATH)
    end
    self:showMessage(_("Connexion au moteur Stockfish…"))
    self._uci_engine:start(function(ok)
        if ok then
            self.plugin:saveSetting("engine", "uci")
            self:showMessage(_("Moteur Stockfish activé."))
        else
            self.plugin:saveSetting("engine", "home")
            self:showMessage(_("Échec de connexion au moteur Stockfish. Retour au moteur maison."))
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Screen close — stop the clock and terminate any spawned UCI engine so it
-- never keeps running in the background after the user leaves this screen.
-- ---------------------------------------------------------------------------

function EchecsScreen:closeScreen()
    if self.clock then self.clock:stop() end
    if self._uci_engine then self._uci_engine:stop() end
    ScreenBase.closeScreen(self)
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
-- Chess clock
-- ---------------------------------------------------------------------------

function EchecsScreen:_createClock()
    local base = self.plugin:getSetting("clock_base_minutes", { w = 10, b = 10 })
    local incr = self.plugin:getSetting("clock_increment_seconds", { w = 0, b = 0 })
    self.clock = ChessClock:new{
        base_minutes      = base,
        increment_seconds = incr,
        on_tick           = function() self:_updateClockDisplay() end,
        on_timeout        = function(color) self:_onClockTimeout(color) end,
    }
end

function EchecsScreen:_updateClockDisplay()
    if not self.clock or not self.clock_text then return end
    local w = self.clock:formatTime(self.clock:getRemainingTime("w"))
    local b = self.clock:formatTime(self.clock:getRemainingTime("b"))
    local marker = (self.clock.turn == "w") and " ⤆ " or " ⤇ "
    self.clock_text:setText(w .. marker .. b)
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function EchecsScreen:_onClockTimeout(color)
    if self.board.status ~= "playing" or self._time_forfeit then return end
    self._time_forfeit = color
    self:_updateClockDisplay()
    self.plugin:saveState(self:serializeState())
    self:updateStatus()
    self:onGameEnd()
end

function EchecsScreen:openClockMenu()
    local enabled = self.plugin:getSetting("clock_enabled", false)
    MenuHelper.openPickerMenu{
        title      = _("Pendule"),
        items      = {
            { id = false, text = _("Désactivée") },
            { id = true,  text = _("Activée") },
        },
        current_id = enabled,
        on_select  = function(id)
            self.plugin:saveSetting("clock_enabled", id)
            if id then
                self:_promptClockTime("w")
            else
                if self.clock then self.clock:stop() end
                self.clock = nil
                self:buildLayout()
                UIManager:setDirty(self, function() return "ui", self.dimen end)
            end
        end,
        parent = self,
    }
end

function EchecsScreen:_promptClockTime(color)
    local InputDialog = require("ui/widget/inputdialog")
    local base = self.plugin:getSetting("clock_base_minutes", { w = 10, b = 10 })
    local incr = self.plugin:getSetting("clock_increment_seconds", { w = 0, b = 0 })
    local label = (color == "w")
        and _("Temps Blancs (minutes + incrément sec.)")
        or  _("Temps Noirs (minutes + incrément sec.)")
    local default_text = string.format("%d + %d", base[color], incr[color])

    local dialog
    dialog = InputDialog:new{
        title = label,
        input = default_text,
        buttons = {{
            {
                text     = _("Annuler"),
                id       = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text             = _("OK"),
                is_enter_default = true,
                callback         = function()
                    local txt = dialog:getInputText()
                    local nb, ni = txt:match("^%s*(%d+)%s*%+%s*(%d+)%s*$")
                    if not nb then
                        self:showMessage(_("Format invalide. Utilisez 'minutes + secondes'."))
                        return
                    end
                    base[color] = math.max(1, tonumber(nb))
                    incr[color] = math.max(0, tonumber(ni))
                    self.plugin:saveSetting("clock_base_minutes", base)
                    self.plugin:saveSetting("clock_increment_seconds", incr)
                    UIManager:close(dialog)
                    if color == "w" then
                        self:_promptClockTime("b")
                    else
                        self:_createClock()
                        if self.board.status == "playing" then self.clock:start() end
                        self:buildLayout()
                        UIManager:setDirty(self, function() return "ui", self.dimen end)
                    end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ---------------------------------------------------------------------------
-- Status bar
-- ---------------------------------------------------------------------------

function EchecsScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self._time_forfeit then
        local winner = (self._time_forfeit == "w") and _("Noirs") or _("Blancs")
        status = winner .. " " .. _("gagnent au temps !")
    else
        local board = self.board
        if board.status == "checkmate" then
            local winner = (board.winner == "w") and _("Blancs") or _("Noirs")
            status = winner .. " " .. _("gagnent par mat !")
        elseif board.status == "stalemate" then
            status = _("Pat — partie nulle.")
        elseif board.status == "draw" then
            status = _("Nulle") .. " (" .. drawReasonLabel(board.draw_reason) .. ")."
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

-- ---------------------------------------------------------------------------
-- PGN export / import
-- ---------------------------------------------------------------------------

local function pgnResultTag(board)
    if board.status == "checkmate" then
        return (board.winner == "w") and "1-0" or "0-1"
    elseif board.status == "stalemate" or board.status == "draw" then
        return "1/2-1/2"
    end
    return "*"
end

function EchecsScreen:_pgnHeaders()
    local white_label, black_label = _("Joueur"), _("Joueur")
    if self.plugin:getSetting("players", 1) == 1 then
        local pc = self.plugin:getSetting("player_color", "w")
        if pc == "w" then black_label = _("IA") else white_label = _("IA") end
    end
    return {
        Event  = _("Partie Échecs"),
        Date   = os.date("%Y.%m.%d"),
        White  = white_label,
        Black  = black_label,
        Result = pgnResultTag(self.board),
    }
end

function EchecsScreen:onExportPGN()
    local PathChooser = require("ui/widget/pathchooser")
    local lfs = require("libs/libkoreader-lfs")
    UIManager:show(PathChooser:new{
        title             = _("Choisir un dossier pour l'export PGN"),
        path              = lfs.currentdir(),
        select_directory  = true,
        select_file       = false,
        show_parent       = self,
        onConfirm         = function(dir) self:_promptPGNFilename(dir) end,
    })
end

function EchecsScreen:_promptPGNFilename(dir)
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = _("Nom du fichier PGN"),
        input = "partie.pgn",
        buttons = {{
            {
                text     = _("Annuler"),
                id       = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text             = _("Enregistrer"),
                is_enter_default = true,
                callback         = function()
                    local filename = dialog:getInputText():gsub("\n$", "")
                    if not filename:lower():match("%.pgn$") then
                        filename = filename .. ".pgn"
                    end
                    UIManager:close(dialog)
                    self:_writePGNFile(dir .. "/" .. filename)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function EchecsScreen:_writePGNFile(path)
    local sans = {}
    for _, entry in ipairs(self.board._move_history) do
        sans[#sans + 1] = entry.san
    end
    local pgn_text = PGN.buildPGN(self:_pgnHeaders(), sans)

    local fh, err = io.open(path, "w")
    if not fh then
        self:showMessage(_("Échec de l'export PGN : ") .. tostring(err))
        return
    end
    fh:write(pgn_text)
    fh:close()
    self:showMessage(_("Partie exportée vers ") .. path)
end

function EchecsScreen:onImportPGN()
    local PathChooser = require("ui/widget/pathchooser")
    local lfs = require("libs/libkoreader-lfs")
    UIManager:show(PathChooser:new{
        title            = _("Choisir un fichier PGN"),
        path             = lfs.currentdir(),
        select_directory = false,
        show_parent      = self,
        onConfirm        = function(path) self:_readPGNFile(path) end,
    })
end

function EchecsScreen:_readPGNFile(path)
    local fh, err = io.open(path, "r")
    if not fh then
        self:showMessage(_("Impossible d'ouvrir le fichier : ") .. tostring(err))
        return
    end
    local text = fh:read("*a")
    fh:close()

    local headers, sans = PGN.parsePGN(text)
    local new_board = ChessBoard:new()
    for i, san in ipairs(sans) do
        if not new_board:makeMoveSAN(san) then
            self:showMessage(_("Coup PGN invalide : ") .. san .. " (#" .. i .. ")")
            return
        end
    end

    self.board = new_board
    self._flipped = false
    self._time_forfeit = nil
    if self.clock then
        self.clock:reset()
        self.clock.turn = self.board.turn
        if self.board.status == "playing" then self.clock:start() end
    end
    self.plugin:saveState(self:serializeState())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    self:showMessage(_("Partie importée (") .. #sans .. " " .. _("coups") .. ").")
end

return EchecsScreen
