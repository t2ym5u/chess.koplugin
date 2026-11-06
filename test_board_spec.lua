local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("ChessBoard", function()
    local Board, PGN

    setup(function()
        Board = require("board")
        PGN   = require("pgn")
    end)


    -- ------------------------------------------------------------------
    -- Helpers for building custom positions
    -- ------------------------------------------------------------------

    local function emptyFlat()
        local flat = {}
        for i = 1, 64 do flat[i] = 0 end
        return flat
    end

    local function idx(r, c) return (r - 1) * 8 + c end

    -- Load a custom position. `pieces` is an array of {r, c, piece}.
    local function loadPosition(pieces, opts)
        opts = opts or {}
        local flat = emptyFlat()
        for _, p in ipairs(pieces) do
            flat[idx(p[1], p[2])] = p[3]
        end
        local b = Board:new()
        b:load{
            sq_flat  = flat,
            turn     = opts.turn or "w",
            castle   = opts.castle or { wK=false, wQ=false, bK=false, bQ=false },
            ep       = opts.ep,
            halfmove = opts.halfmove or 0,
            status   = "playing",
            winner   = nil,
        }
        return b
    end

    -- ------------------------------------------------------------------
    -- Perft — classic move-count regression guard for the generator
    -- ------------------------------------------------------------------

    local function perft(board, depth)
        if depth == 0 then return 1 end
        local moves = board:getLegalMoves()
        if depth == 1 then return #moves end
        local nodes = 0
        for _, m in ipairs(moves) do
            local saved = board:_applyMove(m)
            nodes = nodes + perft(board, depth - 1)
            board:_undoMove(saved)
        end
        return nodes
    end

    describe("perft from the standard start position", function()
        it("depth 1 = 20", function()
            local b = Board:new()
            assert.are.equal(20, perft(b, 1))
        end)

        it("depth 2 = 400", function()
            local b = Board:new()
            assert.are.equal(400, perft(b, 2))
        end)

        it("depth 3 = 8902", function()
            local b = Board:new()
            assert.are.equal(8902, perft(b, 3))
        end)

        it("depth 4 = 197281", function()
            local b = Board:new()
            assert.are.equal(197281, perft(b, 4))
        end)
    end)

    -- ------------------------------------------------------------------
    -- En passant
    -- ------------------------------------------------------------------

    describe("en passant", function()
        it("allows capturing the pawn that just double-stepped", function()
            -- White pawn on e5 (r=4,c=5), black pawn on d5 (r=4,c=4) having
            -- just played d7-d5, so ep target file is d (c=4).
            local b = loadPosition({
                { 8, 5, Board.W_KING }, { 1, 5, Board.B_KING },
                { 4, 5, Board.W_PAWN }, { 4, 4, Board.B_PAWN },
            }, { turn = "w", ep = 4 })

            local moves = b:getMovesForSquare(4, 5)
            local ep_move
            for _, m in ipairs(moves) do
                if m.special == "ep" then ep_move = m end
            end
            assert.is_not_nil(ep_move)
            assert.are.equal(3, ep_move.tr)
            assert.are.equal(4, ep_move.tc)

            assert.is_true(b:makeMove(4, 5, 3, 4))
            assert.are.equal(Board.EMPTY, b.sq[4][4])  -- captured pawn removed
            assert.are.equal(Board.W_PAWN, b.sq[3][4])
        end)
    end)

    -- ------------------------------------------------------------------
    -- Castling
    -- ------------------------------------------------------------------

    describe("castling", function()
        it("allows kingside castling when the path is clear and unattacked", function()
            local b = loadPosition({
                { 8, 5, Board.W_KING }, { 8, 8, Board.W_ROOK },
                { 1, 5, Board.B_KING },
            }, { turn = "w", castle = { wK = true, wQ = false, bK = false, bQ = false } })

            assert.is_true(b:makeMove(8, 5, 8, 7))
            assert.are.equal(Board.W_KING, b.sq[8][7])
            assert.are.equal(Board.W_ROOK, b.sq[8][6])
            assert.are.equal(Board.EMPTY, b.sq[8][8])
        end)

        it("forbids castling when a square in the path is attacked", function()
            local b = loadPosition({
                { 8, 5, Board.W_KING }, { 8, 8, Board.W_ROOK },
                { 1, 6, Board.B_KING }, { 1, 7, Board.B_ROOK },  -- rook attacks g1 (8,7)
            }, { turn = "w", castle = { wK = true, wQ = false, bK = false, bQ = false } })

            local moves = b:getMovesForSquare(8, 5)
            for _, m in ipairs(moves) do
                assert.is_not.equal("castle_k", m.special)
            end
        end)

        it("forbids castling when a square in the path is occupied", function()
            local b = loadPosition({
                { 8, 5, Board.W_KING }, { 8, 8, Board.W_ROOK }, { 8, 7, Board.W_KNIGHT },
                { 1, 5, Board.B_KING },
            }, { turn = "w", castle = { wK = true, wQ = false, bK = false, bQ = false } })

            local moves = b:getMovesForSquare(8, 5)
            for _, m in ipairs(moves) do
                assert.is_not.equal("castle_k", m.special)
            end
        end)
    end)

    -- ------------------------------------------------------------------
    -- Promotion
    -- ------------------------------------------------------------------

    describe("promotion", function()
        it("offers all four promotion pieces one square from the last rank", function()
            local b = loadPosition({
                { 8, 5, Board.W_KING }, { 1, 8, Board.B_KING },
                { 2, 1, Board.W_PAWN },
            }, { turn = "w" })

            local moves = b:getMovesForSquare(2, 1)
            local promos = {}
            for _, m in ipairs(moves) do
                if m.special == "promo" then promos[m.promo_piece] = true end
            end
            assert.is_true(promos[Board.W_QUEEN])
            assert.is_true(promos[Board.W_ROOK])
            assert.is_true(promos[Board.W_BISHOP])
            assert.is_true(promos[Board.W_KNIGHT])
        end)

        it("promotes to the requested piece", function()
            local b = loadPosition({
                { 8, 5, Board.W_KING }, { 1, 8, Board.B_KING },
                { 2, 1, Board.W_PAWN },
            }, { turn = "w" })

            assert.is_true(b:makeMove(2, 1, 1, 1, Board.W_KNIGHT))
            assert.are.equal(Board.W_KNIGHT, b.sq[1][1])
        end)
    end)

    -- ------------------------------------------------------------------
    -- Draw detection
    -- ------------------------------------------------------------------

    describe("insufficient material", function()
        it("declares a draw for bare kings", function()
            local b = loadPosition({ { 8, 5, Board.W_KING }, { 1, 5, Board.B_KING } })
            b:_updateStatus()
            assert.are.equal("draw", b.status)
            assert.are.equal("insufficient_material", b.draw_reason)
        end)

        it("declares a draw for king+bishop vs king", function()
            local b = loadPosition({
                { 8, 5, Board.W_KING }, { 1, 5, Board.B_KING }, { 8, 6, Board.W_BISHOP },
            })
            b:_updateStatus()
            assert.are.equal("draw", b.status)
            assert.are.equal("insufficient_material", b.draw_reason)
        end)

        it("does not declare a draw while a rook is on the board", function()
            local b = loadPosition({
                { 8, 5, Board.W_KING }, { 1, 5, Board.B_KING }, { 8, 1, Board.W_ROOK },
            })
            b:_updateStatus()
            assert.are_not.equal("draw", b.status)
        end)
    end)

    describe("threefold repetition", function()
        it("declares a draw once the same position has occurred three times", function()
            local b = Board:new()  -- standard start position
            -- Shuffle both knights back and forth: Ng1-f3 / Ng8-f6, then back.
            -- Each full cycle (4 plies) returns to the exact start position.
            local shuffle = {
                {8,7, 6,6}, {1,7, 3,6},  -- Ng1-f3, Ng8-f6
                {6,6, 8,7}, {3,6, 1,7},  -- Nf3-g1, Nf6-g8 -> start position, 2nd time
                {8,7, 6,6}, {1,7, 3,6},  -- Ng1-f3, Ng8-f6 (again)
                {6,6, 8,7}, {3,6, 1,7},  -- Nf3-g1, Nf6-g8 -> start position, 3rd time -> draw
            }
            for _, m in ipairs(shuffle) do
                assert.is_true(b:makeMove(m[1], m[2], m[3], m[4]))
            end
            assert.are.equal("draw", b.status)
            assert.are.equal("repetition", b.draw_reason)
        end)
    end)

    -- ------------------------------------------------------------------
    -- Undo / redo
    -- ------------------------------------------------------------------

    describe("redo", function()
        it("restores the position undone by undoMove", function()
            local b = Board:new()
            assert.is_true(b:makeMove(7, 5, 5, 5))  -- e2-e4
            local after_move = b:_currentFlat()

            assert.is_true(b:undoMove())
            assert.are.equal(Board.EMPTY, b.sq[5][5])

            assert.is_true(b:redoMove())
            local after_redo = b:_currentFlat()
            assert.are.same(after_move, after_redo)
        end)

        it("is cleared once a new move is made after an undo", function()
            local b = Board:new()
            assert.is_true(b:makeMove(7, 5, 5, 5))  -- e2-e4
            assert.is_true(b:undoMove())
            assert.is_true(b:makeMove(7, 4, 5, 4))  -- d2-d4, a different move
            assert.is_false(b:redoMove())
        end)

        it("returns false when there is nothing to redo", function()
            local b = Board:new()
            assert.is_false(b:redoMove())
        end)
    end)

    -- ------------------------------------------------------------------
    -- Serialization round-trip (including the new redo stack / draw_reason)
    -- ------------------------------------------------------------------

    describe("serialize / load", function()
        it("round-trips history, future and draw_reason", function()
            local b = Board:new()
            assert.is_true(b:makeMove(7, 5, 5, 5))  -- e2-e4
            assert.is_true(b:undoMove())  -- populates the future/redo stack

            local data = b:serialize()
            local b2 = Board:new()
            assert.is_true(b2:load(data))

            assert.are.equal(#b._history, #b2._history)
            assert.are.equal(#b._future, #b2._future)
            assert.is_true(b2:redoMove())
            assert.are.equal(Board.W_PAWN, b2.sq[5][5])
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)

    -- ------------------------------------------------------------------
    -- SAN generation / PGN import-export (pgn.lua)
    -- ------------------------------------------------------------------

    describe("SAN generation", function()
        it("generates simple pawn and knight moves", function()
            local b = Board:new()
            assert.is_true(b:makeMove(7, 5, 5, 5))  -- e2-e4
            assert.are.equal("e4", b._move_history[1].san)
            assert.is_true(b:makeMove(2, 5, 4, 5))  -- e7-e5
            assert.are.equal("e5", b._move_history[2].san)
            assert.is_true(b:makeMove(8, 7, 6, 6))  -- Ng1-f3
            assert.are.equal("Nf3", b._move_history[3].san)
        end)

        it("marks check and checkmate suffixes (Fool's mate)", function()
            local b = Board:new()
            assert.is_true(b:makeMove(7, 6, 6, 6))  -- f2-f3
            assert.is_true(b:makeMove(2, 5, 4, 5))  -- e7-e5
            assert.is_true(b:makeMove(7, 7, 5, 7))  -- g2-g4
            assert.is_true(b:makeMove(1, 4, 5, 8))  -- Qd8-h4#
            assert.are.equal("checkmate", b.status)
            assert.are.equal("Qh4#", b._move_history[4].san)
        end)

        it("disambiguates by file when two rooks can reach the same square", function()
            local b = loadPosition({
                { 4, 5, Board.W_KING }, { 1, 5, Board.B_KING },
                { 8, 1, Board.W_ROOK }, { 8, 6, Board.W_ROOK },
            }, { turn = "w" })

            local move = { fr = 8, fc = 1, tr = 8, tc = 4, capture = false }
            assert.are.equal("Rad1", PGN.toSAN(b, move))
        end)
    end)

    -- Positions from FEN (board + side to move + castling only).
    local FEN_PIECES = { P=1, R=2, N=3, B=4, Q=5, K=6, p=7, r=8, n=9, b=10, q=11, k=12 }
    local function fromFEN(fen)
        local placement, side, cas = fen:match("^(%S+) (%S+) (%S+)")
        local pieces, r, c = {}, 1, 1
        for ch in placement:gmatch(".") do
            if ch == "/" then r = r + 1; c = 1
            elseif ch:match("%d") then c = c + tonumber(ch)
            else pieces[#pieces + 1] = { r, c, FEN_PIECES[ch] }; c = c + 1 end
        end
        return loadPosition(pieces, { turn = side, castle = {
            wK = cas:find("K") ~= nil, wQ = cas:find("Q") ~= nil,
            bK = cas:find("k") ~= nil, bQ = cas:find("q") ~= nil } })
    end

    describe("perft on tactical positions", function()
        -- Reference counts from the chess programming wiki. Position 3 is
        -- full of pawn checks, which went unseen before 1.3.0.
        it("Kiwipete depth 2 = 2039", function()
            local b = fromFEN("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq")
            assert.are.equal(48, perft(b, 1))
            assert.are.equal(2039, perft(b, 2))
        end)
        it("position 3 depth 4 = 43238", function()
            local b = fromFEN("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w -")
            assert.are.equal(14, perft(b, 1))
            assert.are.equal(191, perft(b, 2))
            assert.are.equal(2812, perft(b, 3))
            assert.are.equal(43238, perft(b, 4))
        end)
        it("a king may not step next to an enemy pawn's attack", function()
            -- White king e1, black pawn e3 attacks d2 and f2.
            local b = fromFEN("4k3/8/8/8/8/4p3/8/4K3 w -")
            for _, m in ipairs(b:getLegalMoves()) do
                assert.is_false(m.tr == 7 and (m.tc == 4 or m.tc == 6))
            end
            assert.is_true(fromFEN("4k3/8/8/8/8/8/3p4/4K3 w -"):isInCheck("w"))
        end)
    end)

    describe("AI time budget", function()
        local function midgame()
            return fromFEN("r1bq1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N1PN2/PP3PPP/R2QKB1R w KQ")
        end

        it("single-pass evaluation equals the reference evaluation", function()
            math.randomseed(11)
            local checked = 0
            for _ = 1, 10 do
                local b = Board:new()
                for _ = 1, 80 do
                    if b.status ~= "playing" then break end
                    assert.are.equal(b:_evaluateReference(), b:_evaluate())
                    checked = checked + 1
                    local ms = b:getLegalMoves()
                    local m = ms[math.random(#ms)]
                    b:makeMove(m.fr, m.fc, m.tr, m.tc, m.promo_piece)
                end
            end
            assert.is_true(checked > 300)
        end)

        it("returns a legal move even when the budget is already spent", function()
            local b = midgame()
            local before = b:_currentFlat()
            local scale = Board.AI_TIME_SCALE
            Board.AI_TIME_SCALE = 0
            local move = b:getAIMoveForLevel("hard")
            Board.AI_TIME_SCALE = scale
            assert.is_not_nil(move)
            -- the interrupted search left the position as it was
            assert.are.same(before, b:_currentFlat())
            assert.are.equal("w", b.turn)
            assert.is_true(b:makeMove(move.fr, move.fc, move.tr, move.tc, move.promo_piece))
        end)

        it("finds a mate in one and stays well within its budget", function()
            -- Back-rank mate: Ra1-a8#.
            local b = fromFEN("6k1/5ppp/8/8/8/8/8/R5K1 w -")
            local t0 = os.clock()
            local move = b:getAIMoveForLevel("hard")
            assert.is_true(os.clock() - t0 < 2.5)
            assert.are.same({ 8, 1, 1, 1 }, { move.fr, move.fc, move.tr, move.tc })
        end)

        it("keeps a hard move within its budget at Kobo speed", function()
            -- 0.04 ~ a Kobo Aura on a desktop: 2.3 s of Kobo is ~0.09 s here.
            local b = midgame()
            local scale = Board.AI_TIME_SCALE
            Board.AI_TIME_SCALE = 0.04
            local t0 = os.clock()
            assert.is_not_nil(b:getAIMoveForLevel("hard"))
            local dt = os.clock() - t0
            Board.AI_TIME_SCALE = scale
            assert.is_true(dt < 0.15)
            assert.is_true(b.ai_depth_reached >= 2)
        end)
    end)

    describe("AI levels", function()
        local function key(m) return m.fr .. "," .. m.fc .. "," .. m.tr .. "," .. m.tc end

        it("are three distinct settings within 2.5 s", function()
            local L = Board.AI_LEVELS
            assert.is_true(L.easy.depth < L.medium.depth)
            assert.is_true(L.medium.depth < L.hard.depth)
            assert.is_not_nil(L.easy.margin)
            assert.is_true(L.easy.blunder > 0 and L.easy.blunder < 1)
            assert.is_nil(L.medium.margin)
            assert.is_nil(L.hard.margin)
            for _, lv in pairs(L) do assert.is_true(lv.budget <= 2.5) end
        end)

        it("scores a stalemate at the search horizon as a draw", function()
            -- White Kf6 Qg1, black Kh8: Qg6 stalemates.
            local b = loadPosition({ {1, 8, Board.B_KING}, {3, 6, Board.W_KING},
                                     {8, 7, Board.W_QUEEN} })
            local saved = b:_applyMove({ fr = 8, fc = 7, tr = 3, tc = 7 })
            assert.are.equal(0, (b:_alphaBeta(0, -math.huge, math.huge, false, 1)))
            b:_undoMove(saved)
            for _, lv in ipairs({ "easy", "medium", "hard" }) do
                for seed = 1, 5 do
                    math.randomseed(seed)
                    local m = b:getAIMoveForLevel(lv)
                    assert.are_not.equal("8,7,3,7", key(m))
                end
            end
        end)

        it("sees a mate at the search horizon and always plays a mate in one", function()
            for seed = 1, 10 do
                math.randomseed(seed)
                local b = fromFEN("6k1/5ppp/8/8/8/8/8/R5K1 w -")
                local m = b:getAIMoveForLevel("easy")
                assert.are.equal("8,1,1,1", key(m))
            end
        end)

        it("scores a repeated position as a draw", function()
            -- 1.e4 Nf6 2.Nf3 Ng8 3.Ng1: ...Nf6 now repeats the position
            -- after 1...Nf6, which the plain evaluation does not score 0.
            local b = Board:new()
            for _, m in ipairs({ {7,5,5,5}, {1,7,3,6}, {8,7,6,6}, {3,6,1,7}, {6,6,8,7} }) do
                assert.is_true(b:makeMove(m[1], m[2], m[3], m[4]))
            end
            local saved = b:_applyMove({ fr = 1, fc = 7, tr = 3, tc = 6 })
            assert.are_not.equal(0, b:_searchEval())
            b:_undoMove(saved)
            b:getAIMove(1, nil, { margin = 0 })
            assert.are.equal(0, b.ai_root_values["1,7,3,6"])
        end)

        it("drives a lone king to mate instead of drawing (KQ vs K)", function()
            for _, lv in ipairs({ "medium", "hard" }) do
                for seed = 1, 3 do
                    math.randomseed(seed)
                    local b = loadPosition({ {1, 5, Board.B_KING}, {8, 1, Board.W_KING},
                                             {8, 4, Board.W_QUEEN} })
                    local plies = 0
                    while b.status == "playing" and plies < 120 do
                        local m
                        if b.turn == "w" then
                            m = b:getAIMoveForLevel(lv)
                        else
                            local ms = b:getLegalMoves(); m = ms[math.random(#ms)]
                        end
                        assert.is_true(b:makeMove(m.fr, m.fc, m.tr, m.tc, m.promo_piece))
                        plies = plies + 1
                    end
                    assert.are.equal("checkmate", b.status)
                end
            end
        end)

        it("Medium and Hard take a hanging queen", function()
            -- Black queen on d4 attacked by the knight on f3, undefended.
            local b = loadPosition({ {1, 5, Board.B_KING}, {5, 4, Board.B_QUEEN},
                                     {8, 5, Board.W_KING}, {6, 6, Board.W_KNIGHT},
                                     {7, 1, Board.W_PAWN} })
            for _, lv in ipairs({ "medium", "hard" }) do
                assert.are.equal("6,6,5,4", key(b:getAIMoveForLevel(lv)))
            end
        end)

        it("Easy is reproducible for a given random seed", function()
            local function game()
                math.randomseed(42)
                local b = Board:new()
                local seq = {}
                for _ = 1, 10 do
                    local m = b:getAIMoveForLevel("easy")
                    b:makeMove(m.fr, m.fc, m.tr, m.tc, m.promo_piece)
                    seq[#seq + 1] = key(m)
                end
                return table.concat(seq, " ")
            end
            assert.are.equal(game(), game())
        end)
    end)

    describe("PGN export/import round-trip", function()
        it("re-creates the same position from exported PGN", function()
            local b = Board:new()
            local moves = {
                {7,5, 5,5}, {2,5, 4,5},   -- e4 e5
                {8,7, 6,6}, {1,7, 3,6},   -- Nf3 Nf6
                {8,6, 5,3},               -- Bc4
            }
            for _, m in ipairs(moves) do
                assert.is_true(b:makeMove(m[1], m[2], m[3], m[4]))
            end

            local sans = {}
            for _, entry in ipairs(b._move_history) do sans[#sans + 1] = entry.san end
            local pgn_text = PGN.buildPGN({ White = "A", Black = "B" }, sans)

            local headers, parsed_sans = PGN.parsePGN(pgn_text)
            assert.are.equal("A", headers.White)
            assert.are.equal(#sans, #parsed_sans)

            local b2 = Board:new()
            for _, san in ipairs(parsed_sans) do
                assert.is_true(b2:makeMoveSAN(san), "failed to replay: " .. san)
            end

            assert.are.same(b:_currentFlat(), b2:_currentFlat())
            assert.are.equal(b.turn, b2.turn)
        end)
    end)
end)
