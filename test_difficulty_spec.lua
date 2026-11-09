-- Difficulty guarantees of the built-in chess engine: the level table is
-- ordered, every level plays legal moves and a mate in one, Medium and Hard
-- take a hanging queen and parry a mate in one (Easy is deliberately loose
-- and may not), Easy replays under the same seed and varies with it, and
-- each level stays within its think time at Kobo speed. No full matches.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("Chess difficulty", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    after_each(function()
        Board.AI_TIME_SCALE = 1
    end)

    local IDS = { "easy", "medium", "hard" }

    local function key(m) return m.fr .. "," .. m.fc .. "," .. m.tr .. "," .. m.tc end

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

    -- True when the side to move has a move that mates at once.
    local function hasMateInOne(b)
        for _, m in ipairs(b:getLegalMoves()) do
            b:makeMove(m.fr, m.fc, m.tr, m.tc, m.promo_piece)
            local mate = b.status == "checkmate"
            b:undoMove()
            if mate then return true end
        end
        return false
    end

    -- Seeded random positions, `plies` random moves from the start.
    local function randomPositions(n, seed, plies)
        math.randomseed(seed)
        local out = {}
        for _ = 1, n * 5 do
            if #out >= n then break end
            local b = Board:new()
            for _ = 1, plies do
                if b.status ~= "playing" then break end
                local ms = b:getLegalMoves()
                local m = ms[math.random(#ms)]
                b:makeMove(m.fr, m.fc, m.tr, m.tc, m.promo_piece)
            end
            if b.status == "playing" then out[#out + 1] = b end
        end
        return out
    end

    -- Easy's first moves under one seed.
    local function easyLine(seed)
        math.randomseed(seed)
        local b = Board:new()
        local seq = {}
        for _ = 1, 10 do
            local m = b:getAIMoveForLevel("easy")
            b:makeMove(m.fr, m.fc, m.tr, m.tc, m.promo_piece)
            seq[#seq + 1] = key(m)
        end
        return table.concat(seq, " ")
    end

    it("are three distinct settings within 2.5 s", function()
        local L = Board.AI_LEVELS
        assert.is_true(L.easy.depth < L.medium.depth)
        assert.is_true(L.medium.depth < L.hard.depth)
        assert.is_true(L.easy.budget <= L.medium.budget and L.medium.budget <= L.hard.budget)
        assert.is_not_nil(L.easy.margin)
        assert.is_true(L.easy.blunder > 0 and L.easy.blunder < 1)
        assert.is_nil(L.medium.margin)
        assert.is_nil(L.hard.margin)
        for _, lv in pairs(L) do assert.is_true(lv.budget <= 2.5) end
    end)

    it("finds a mate in one and stays well within its budget", function()
        -- Back-rank mate: Ra1-a8#.
        local b = fromFEN("6k1/5ppp/8/8/8/8/8/R5K1 w -")
        local t0 = os.clock()
        local move = b:getAIMoveForLevel("hard")
        assert.is_true(os.clock() - t0 < 2.5)
        assert.are.same({ 8, 1, 1, 1 }, { move.fr, move.fc, move.tr, move.tc })
    end)

    it("sees a mate at the search horizon and always plays a mate in one", function()
        for seed = 1, 10 do
            math.randomseed(seed)
            local b = fromFEN("6k1/5ppp/8/8/8/8/8/R5K1 w -")
            local m = b:getAIMoveForLevel("easy")
            assert.are.equal("8,1,1,1", key(m))
        end
    end)

    it("every level plays a mate in one, with either colour", function()
        -- The fool's mate for Black: 1.f3 e5 2.g4, then ...Qd8-h4#.
        local fools = Board:new()
        for _, m in ipairs({ {7,6,6,6}, {2,5,4,5}, {7,7,5,7} }) do
            assert.is_true(fools:makeMove(m[1], m[2], m[3], m[4]))
        end
        for _, lv in ipairs(IDS) do
            for seed = 1, 3 do
                math.randomseed(seed)
                local m = fools:getAIMoveForLevel(lv)
                fools:makeMove(m.fr, m.fc, m.tr, m.tc, m.promo_piece)
                assert.are.equal("checkmate", fools.status, lv .. " missed the mate")
                fools:undoMove()
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

    it("Medium and Hard parry a mate in one", function()
        local threats = {
            -- Black threatens ...Ra8-a1# on the back rank.
            "r5k1/5ppp/8/8/7N/8/5PPP/6K1 w -",
            -- White threatens Qh5xf7# (bishop on c4 behind it).
            "r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq",
        }
        for _, fen in ipairs(threats) do
            -- The threat is real: pass the move and the opponent mates.
            local probe = fromFEN(fen)
            probe.turn = (probe.turn == "w") and "b" or "w"
            assert.is_true(hasMateInOne(probe), "no threat in " .. fen)
            for _, lv in ipairs({ "medium", "hard" }) do
                for seed = 1, 3 do
                    math.randomseed(seed)
                    local b = fromFEN(fen)
                    local m = b:getAIMoveForLevel(lv)
                    assert.is_true(b:makeMove(m.fr, m.fc, m.tr, m.tc, m.promo_piece))
                    assert.is_false(hasMateInOne(b), lv .. " allowed a mate in " .. fen)
                end
            end
        end
    end)

    it("every level plays legal moves in random positions", function()
        Board.AI_TIME_SCALE = 0.04
        for _, plies in ipairs({ 6, 20, 40 }) do
            for _, b in ipairs(randomPositions(3, plies, plies)) do
                for _, lv in ipairs(IDS) do
                    local before = b:_currentFlat()
                    local m = b:getAIMoveForLevel(lv)
                    assert.is_not_nil(m)
                    assert.are.same(before, b:_currentFlat())
                    local ok = false
                    for _, l in ipairs(b:getLegalMoves()) do
                        if key(l) == key(m) then ok = true end
                    end
                    assert.is_true(ok, lv .. " played an illegal move")
                end
            end
        end
    end)

    it("keeps a hard move within its budget at Kobo speed", function()
        -- 0.04 ~ a Kobo Aura on a desktop: 2.3 s of Kobo is ~0.09 s here.
        local b = fromFEN("r1bq1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N1PN2/PP3PPP/R2QKB1R w KQ")
        Board.AI_TIME_SCALE = 0.04
        local t0 = os.clock()
        assert.is_not_nil(b:getAIMoveForLevel("hard"))
        local dt = os.clock() - t0
        assert.is_true(dt < 0.15)
        assert.is_true(b.ai_depth_reached >= 2)
    end)

    it("keeps every level within its budget at Kobo speed", function()
        Board.AI_TIME_SCALE = 0.04
        local worst = 0
        for _, b in ipairs(randomPositions(4, 77, 16)) do
            for _, lv in ipairs(IDS) do
                local t0 = os.clock()
                b:getAIMoveForLevel(lv)
                local dt = (os.clock() - t0) * 25
                if dt > worst then worst = dt end
            end
        end
        assert.is_true(worst <= 2.5, string.format("slowest Kobo move %.2f s", worst))
    end)

    it("Easy is reproducible for a given random seed", function()
        assert.are.equal(easyLine(42), easyLine(42))
    end)

    it("Easy varies with the seed", function()
        local seen, distinct = {}, 0
        for seed = 1, 4 do
            local s = easyLine(seed)
            if not seen[s] then seen[s] = true; distinct = distinct + 1 end
        end
        assert.is_true(distinct >= 2, "Easy played the same line for every seed")
    end)
end)
