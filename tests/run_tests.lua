-- Headless test runner for the Showdown Clone engine.
-- Runs under plain Lua 5.1+ (no WoW API). Usage:
--   lua5.1 tests/run_tests.lua     (from the repo root)
--   luajit tests/run_tests.lua
--   python3 tests/run_tests.py     (LuaJIT via lupa, same suite)

local ROOT = arg and arg[0] and arg[0]:match("^(.*)[/\\]") or "."
if ROOT == "tests" or ROOT == "./tests" or ROOT == ".\\tests" then ROOT = ".." end
package.path = ROOT .. "/?.lua;" .. ROOT .. "/?/init.lua;" .. package.path

local passed, failed = 0, 0
local failures = {}

local function ok(cond, name)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = name
        print("FAIL " .. name)
    end
end

local function eq(a, b, name)
    ok(a == b, name .. " (expected " .. tostring(b) .. ", got " .. tostring(a) .. ")")
end

local function approx(a, b, tol, name)
    ok(math.abs(a - b) <= tol, name .. " (expected ~" .. tostring(b) .. ", got " .. tostring(a) .. ")")
end

local Types = require("Core.Data.Types")
local Moves = require("Core.Data.Moves")
local PokemonData = require("Core.Data.Pokemon")
local PRNG = require("Core.Util.PRNG")
local Json = require("Core.Libs.Json")
local Stats = require("Core.Stats")
local BattleEngine = require("Core.BattleEngine")
local Bot = require("Core.Bot")
local Serializer = require("Core.Util.Serializer")
local Net = require("Core.Net")

----------------------------------------------------------------------
-- Data integrity
----------------------------------------------------------------------
do
    eq(PokemonData.count(), 151, "151 Pokemon defined")

    for id = 1, 151 do
        local p = PokemonData.get(id)
        ok(p ~= nil, "Pokemon #" .. id .. " exists")
        ok(#p.types >= 1 and #p.types <= 2, "Pokemon #" .. id .. " has 1-2 types")
        for _, t in ipairs(p.types) do
            ok(Types.isValid(t), "Pokemon #" .. id .. " type '" .. t .. "' valid")
        end
        for _, k in ipairs({ "hp", "atk", "def", "spa", "spd", "spe" }) do
            ok(type(p.base[k]) == "number" and p.base[k] > 0, "Pokemon #" .. id .. " base." .. k .. " > 0")
        end
        ok(#p.learnset >= 1, "Pokemon #" .. id .. " has a learnset")
    end

    for id = 1, 151 do
        local p = PokemonData.get(id)
        local lastLv = 0
        for _, entry in ipairs(p.learnset) do
            local lv, moveId = entry[1], entry[2]
            ok(Moves.exists(moveId), p.name .. " learnset move '" .. tostring(moveId) .. "' exists")
            ok(lv >= lastLv, p.name .. " learnset sorted by level at " .. tostring(moveId))
            lastLv = lv
        end
    end

    for id, m in pairs(Moves.list) do
        ok(Types.isValid(m.type), "Move " .. id .. " type valid")
        ok(m.acc >= 0 and m.acc <= 100, "Move " .. id .. " acc in range")
        ok(m.pp > 0, "Move " .. id .. " pp > 0")
        ok(m.power >= 0, "Move " .. id .. " power >= 0")
    end

    -- Gen 1 category is determined by move TYPE (physical/special types)
    eq(Types.categoryFor("Bug"), "physical", "Gen 1: Bug is a physical type")
    eq(Types.categoryFor("Poison"), "physical", "Gen 1: Poison is a physical type")
    eq(Types.categoryFor("Ghost"), "physical", "Gen 1: Ghost is a physical type")
    eq(Types.categoryFor("Fire"), "special", "Gen 1: Fire is a special type")
    eq(Types.categoryFor("Ice"), "special", "Gen 1: Ice is a special type")
    eq(Types.categoryFor("Dragon"), "special", "Gen 1: Dragon is a special type")

    -- Elemental punches are SPECIAL in Gen 1 (Electric/Fire/Ice are special types)
    eq(Moves.get("ThunderPunch").cat, nil, "ThunderPunch has no cat override (special via type)")
    eq(Types.categoryFor(Moves.get("ThunderPunch").type), "special", "ThunderPunch is special in Gen 1")
    eq(Types.categoryFor(Moves.get("FirePunch").type), "special", "FirePunch is special in Gen 1")
    eq(Types.categoryFor(Moves.get("IcePunch").type), "special", "IcePunch is special in Gen 1")

    -- Bug moves are PHYSICAL in Gen 1
    eq(Types.categoryFor(Moves.get("LeechLife2").type), "physical", "Leech Life is physical in Gen 1")
    eq(Types.categoryFor(Moves.get("PinMissile").type), "physical", "Pin Missile is physical in Gen 1")
    eq(Types.categoryFor(Moves.get("Twineedle").type), "physical", "Twineedle is physical in Gen 1")

    -- Horn Drill is an OHKO move: 30% acc, 5 PP, KOs on hit
    local hd = Moves.get("HornDrill2")
    eq(hd.acc, 30, "Horn Drill accuracy 30")
    eq(hd.pp, 5, "Horn Drill PP 5")
    eq(hd.fixed, "ohko", "Horn Drill is an OHKO move")

    -- Chansey Gen 1 Special is 105 (not the modern SpA 35 / SpD 105 split)
    eq(PokemonData.get(113).base.spa, 105, "Chansey Gen 1 Special = 105")
    eq(PokemonData.get(113).base.spd, 105, "Chansey Gen 1 Special (def) = 105")

    -- bot teams reference valid species and moves
    for _, def in ipairs(Bot.TEAMS) do
        ok(#def.team >= 1 and #def.team <= 6, "Bot " .. def.name .. " has 1-6 Pokemon")
        for _, member in ipairs(def.team) do
            ok(PokemonData.get(member.id) ~= nil, "Bot " .. def.name .. " species #" .. member.id .. " valid")
            ok(member.level >= 1 and member.level <= 100, "Bot " .. def.name .. " level in range")
            if member.moves then
                for _, mv in ipairs(member.moves) do
                    ok(Moves.exists(mv), "Bot " .. def.name .. " move '" .. tostring(mv) .. "' valid")
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- Type chart
----------------------------------------------------------------------
do
    eq(Types.getEffectiveness("Water", "Fire"), 2, "Water SE vs Fire")
    eq(Types.getEffectiveness("Fire", "Water"), 0.5, "Fire NVE vs Water")
    eq(Types.getEffectiveness("Electric", "Ground"), 0, "Electric no effect vs Ground")
    eq(Types.getEffectiveness("Normal", "Ghost"), 0, "Normal no effect vs Ghost")
    eq(Types.getEffectiveness("Ghost", "Psychic"), 0, "Gen 1: Ghost no effect vs Psychic")
    eq(Types.getEffectiveness("Bug", "Poison"), 2, "Gen 1: Bug SE vs Poison")
    eq(Types.getEffectiveness("Poison", "Bug"), 2, "Gen 1: Poison SE vs Bug")
    eq(Types.getEffectiveness("Ice", "Fire"), 1, "Gen 1: Ice neutral vs Fire (0.5x is Gen 2+)")
    eq(Types.getEffectiveness("Poison", "Ground"), 0.5, "Poison NVE vs Ground")
    eq(Types.getEffectiveness("Poison", "Rock"), 0.5, "Poison NVE vs Rock")
    eq(Types.getEffectiveness("Grass", "Fire"), 0.5, "Grass NVE vs Fire")
    eq(Types.getEffectiveness("Grass", "Water"), 2, "Grass SE vs Water")
    eq(Types.getEffectivenessVs("Water", "Fire", "Flying"), 2, "Water SE vs Fire, neutral vs Flying")
    eq(Types.getEffectivenessVs("Electric", "Water", "Dragon"), 1, "Electric SE vs Water, NVE vs Dragon")
    eq(Types.getEffectivenessVs("Ice", "Grass", "Flying"), 4, "Ice SE vs Grass/Flying")
    eq(Types.getEffectivenessVs("Fighting", "Normal", "Rock"), 4, "Fighting SE vs Normal/Rock")
end

----------------------------------------------------------------------
-- PRNG determinism
----------------------------------------------------------------------
do
    local a = PRNG.new(12345)
    local b = PRNG.new(12345)
    local same = true
    for _ = 1, 100 do
        if a:nextFloat() ~= b:nextFloat() then same = false break end
    end
    ok(same, "PRNG same seed same sequence")

    local c = PRNG.new(99999)
    local diff = false
    for _ = 1, 100 do
        if a:nextFloat() ~= c:nextFloat() then diff = true break end
    end
    ok(diff, "PRNG different seed different sequence")

    local r = PRNG.new(1)
    local inRange = true
    for _ = 1, 1000 do
        local f = r:nextFloat()
        if f < 0 or f >= 1 then inRange = false break end
    end
    ok(inRange, "PRNG nextFloat in [0,1)")

    local r2 = PRNG.new(7)
    local intOk = true
    for _ = 1, 1000 do
        local v = r2:nextInt(5, 10)
        if v < 5 or v > 10 then intOk = false break end
    end
    ok(intOk, "PRNG nextInt in range")

    local r3 = PRNG.new(42)
    local hits = 0
    for _ = 1, 10000 do if r3:chance(50) then hits = hits + 1 end end
    approx(hits / 10000, 0.5, 0.03, "PRNG chance(50) ~ 50%")
end

----------------------------------------------------------------------
-- Stats (Showdown-style: level only)
----------------------------------------------------------------------
do
    local species = PokemonData.get(6) -- Charizard
    local stats = Stats.computeStats(species, 50)
    ok(stats.hp > 100, "Charizard Lv50 HP > 100 (got " .. stats.hp .. ")")
    eq(stats.spa, stats.spd, "Gen 1: spa == spd")

    local s50 = Stats.computeStats(species, 50)
    local s100 = Stats.computeStats(species, 100)
    ok(s100.hp > s50.hp, "Lv100 HP > Lv50 HP")
    ok(s100.atk > s50.atk, "Lv100 Atk > Lv50 Atk")

    -- level 1 still has positive stats
    local s1 = Stats.computeStats(PokemonData.get(1), 1)
    ok(s1.hp > 0 and s1.atk > 0, "Lv1 stats positive")

    -- Mewtwo L100 special is huge
    local mew = Stats.computeStats(PokemonData.get(150), 100)
    ok(mew.spa > 250, "Mewtwo L100 spa > 250 (got " .. mew.spa .. ")")
end

----------------------------------------------------------------------
-- Pokemon instance creation + legal moves
----------------------------------------------------------------------
do
    local p = BattleEngine.newPokemon(25, 50) -- Pikachu
    eq(p.name, "Pikachu", "newPokemon name")
    eq(p.level, 50, "newPokemon level")
    eq(p.hp, p.maxHp, "newPokemon full HP")
    ok(#p.moves >= 1 and #p.moves <= 4, "newPokemon 1-4 moves")
    eq(p.types[1], "Electric", "Pikachu type")

    -- default level is 100
    local p100 = BattleEngine.newPokemon(1)
    eq(p100.level, 100, "newPokemon default level 100")

    -- default moveset is the 4 most recent at that level
    local bulb = BattleEngine.newPokemon(1, 40)
    local ids = {}
    for _, m in ipairs(bulb.moves) do ids[#ids + 1] = m.id end
    local hasSolar = false
    for _, id in ipairs(ids) do if id == "SolarBeam" then hasSolar = true end end
    ok(hasSolar, "Bulbasaur L40 knows SolarBeam")

    -- explicit moves are respected
    local custom = BattleEngine.newPokemon(1, 50, { moves = { "Tackle", "Growl" } })
    eq(#custom.moves, 2, "custom moveset count")
    eq(custom.moves[1].id, "Tackle", "custom move 1")
    eq(custom.moves[2].id, "Growl", "custom move 2")

    -- illegal move ids are dropped
    local bad = BattleEngine.newPokemon(1, 50, { moves = { "Tackle", "NotAMove" } })
    eq(#bad.moves, 1, "illegal move dropped")

    -- legalMoves returns all learnable moves at a level
    local legal = BattleEngine.legalMoves(PokemonData.get(25), 50)
    ok(#legal >= 4, "Pikachu L50 has >= 4 legal moves")
    local hasThunderbolt = false
    for _, id in ipairs(legal) do if id == "Thunderbolt" then hasThunderbolt = true end end
    ok(hasThunderbolt, "Pikachu L50 legal moves include Thunderbolt")

    -- nickname
    local nick = BattleEngine.newPokemon(25, 50, { nickname = "Sparky" })
    eq(nick.name, "Sparky", "nickname applied")
end

----------------------------------------------------------------------
-- Battle engine: damage, turns, KO
----------------------------------------------------------------------
do
    local function runBattle(seed, movesA, movesB)
        local a1 = BattleEngine.newPokemon(6, 50, { moves = movesA })
        local b1 = BattleEngine.newPokemon(9, 50, { moves = movesB })
        local battle = BattleEngine.newBattle({ a1 }, { b1 }, { mode = "bot", seed = seed })
        local log = {}
        battle.onLog = function(m) log[#log + 1] = m end
        local turns = 0
        while not battle.over and turns < 300 do
            turns = turns + 1
            battle:runTurn({
                [1] = { type = "move", index = 1 },
                [2] = { type = "move", index = 1 },
            })
        end
        return log, battle
    end

    local logA, battleA = runBattle(123, { "Flamethrower" }, { "WaterGun" })
    local logB, battleB = runBattle(123, { "Flamethrower" }, { "WaterGun" })
    eq(#logA, #logB, "deterministic battle: same log length")
    local sameLog = true
    for i = 1, #logA do
        if logA[i] ~= logB[i] then sameLog = false break end
    end
    ok(sameLog, "deterministic battle: identical logs")
    ok(battleA.over, "battle eventually ends")
    ok(battleA.winner == 1 or battleA.winner == 2, "battle has a winner")

    -- different seeds usually differ
    local logC = runBattle(999, { "Flamethrower" }, { "WaterGun" })
    local diff = false
    for i = 1, math.min(#logA, #logC) do
        if logA[i] ~= logC[i] then diff = true break end
    end
    ok(diff, "different seed -> different battle")

    -- type effectiveness matters
    local atk = BattleEngine.newPokemon(9, 50, { moves = { "Surf" } })
    local defFire = BattleEngine.newPokemon(6, 50)
    local defWater = BattleEngine.newPokemon(9, 50)
    local surf = Moves.get("Surf")
    local b1 = BattleEngine.newBattle({ atk }, { defFire }, { seed = 5 })
    local b2 = BattleEngine.newBattle({ atk }, { defWater }, { seed = 5 })
    local dmgFire = b1:calcDamage(atk, defFire, surf)
    local dmgWater = b2:calcDamage(atk, defWater, surf)
    ok(dmgFire > dmgWater, "Surf does more to Fire than to Water")

    -- immunity: Electric vs Ground
    local raichu = BattleEngine.newPokemon(26, 50, { moves = { "Thunderbolt" } })
    local diglett = BattleEngine.newPokemon(50, 50)
    local b4 = BattleEngine.newBattle({ raichu }, { diglett }, { seed = 1 })
    local res = b4:useMove(1, 1)
    ok(res.immune, "Electric move immune vs Ground")

    -- status: Thunder Wave paralyzes
    local b5 = BattleEngine.newBattle(
        { BattleEngine.newPokemon(25, 50, { moves = { "ThunderWave" } }) },
        { BattleEngine.newPokemon(16, 50) },
        { seed = 77 })
    local r5 = b5:useMove(1, 1)
    ok(r5.hit, "Thunder Wave hits")
    eq(b5:active(2).status, "paralysis", "Thunder Wave paralyzes")

    -- burn residual damage
    local b6 = BattleEngine.newBattle(
        { BattleEngine.newPokemon(4, 50) },
        { BattleEngine.newPokemon(1, 50) },
        { seed = 3 })
    b6:active(2).status = "burn"
    local hpBefore = b6:active(2).hp
    b6:applyResidual()
    ok(b6:active(2).hp < hpBefore, "burn deals residual damage")

    -- switching resets stat stages
    local p = BattleEngine.newPokemon(6, 50)
    p.stages.atk = 3
    local b7 = BattleEngine.newBattle(
        { p, BattleEngine.newPokemon(9, 50) },
        { BattleEngine.newPokemon(1, 50) },
        { seed = 1 })
    b7:forceSwitch(1, 2)
    eq(b7:active(1).stages.atk, 0, "switch resets stages")

    -- forfeit ends the battle
    local b8 = BattleEngine.newBattle(
        { BattleEngine.newPokemon(6, 50) },
        { BattleEngine.newPokemon(9, 50) },
        { seed = 1 })
    local over8 = b8:runTurn({ [1] = { type = "forfeit" } })
    ok(over8, "forfeit ends battle")
    eq(b8.winner, 2, "forfeit gives opponent the win")

    -- OHKO move (Horn Drill): KOs when user level >= target level
    local bOhko = BattleEngine.newBattle(
        { BattleEngine.newPokemon(34, 100, { moves = { "HornDrill2" } }) }, -- Nidoking L100
        { BattleEngine.newPokemon(113, 100) },                              -- Chansey L100
        { seed = 42 })
    -- Force a hit by checking calcDamage directly (accuracy is 30%, so we
    -- test the damage value, not the hit chance)
    local nido = bOhko:active(1)
    local chansey = bOhko:active(2)
    local hdMove = Moves.get("HornDrill2")
    eq(bOhko:calcDamage(nido, chansey, hdMove), chansey.hp, "Horn Drill OHKO damage = target HP (equal level)")

    -- OHKO fails when user level < target level
    local bOhko2 = BattleEngine.newBattle(
        { BattleEngine.newPokemon(34, 50, { moves = { "HornDrill2" } }) }, -- Nidoking L50
        { BattleEngine.newPokemon(113, 100) },                            -- Chansey L100
        { seed = 42 })
    eq(bOhko2:calcDamage(bOhko2:active(1), bOhko2:active(2), hdMove), 0, "Horn Drill fails when user level < target level")

    -- Multi-hit move deals multiple hits
    local bMulti = BattleEngine.newBattle(
        { BattleEngine.newPokemon(6, 100, { moves = { "PinMissile" } }) }, -- Charizard with Pin Missile
        { BattleEngine.newPokemon(113, 100) },                             -- Chansey
        { seed = 123 })
    local pinMissile = Moves.get("PinMissile")
    local dmg = bMulti:calcDamage(bMulti:active(1), bMulti:active(2), pinMissile)
    ok(dmg > 0, "Pin Missile calcDamage > 0 per hit")
    -- Run a full useMove and verify total damage is a multiple of per-hit damage
    local hpBeforeMulti = bMulti:active(2).hp
    -- Pin Missile has 85 acc; retry seeds until it hits
    local hitResult
    for s = 1, 50 do
        local bt = BattleEngine.newBattle(
            { BattleEngine.newPokemon(6, 100, { moves = { "PinMissile" } }) },
            { BattleEngine.newPokemon(113, 100) },
            { seed = s })
        local r = bt:useMove(1, 1)
        if r.hit and not r.immune then
            hitResult = r
            break
        end
    end
    ok(hitResult ~= nil and hitResult.hit, "Pin Missile eventually hits")
    if hitResult then
        local perHit = bMulti:calcDamage(bMulti:active(1), bMulti:active(2), pinMissile)
        ok(perHit > 0, "Pin Missile per-hit damage > 0")
        -- total damage should be >= 2x per-hit (at least 2 hits)
        ok(hitResult.damage >= perHit * 2, "Pin Missile multi-hit total >= 2x per-hit damage")
    end
end

----------------------------------------------------------------------
-- Full AI battles across all 151 species
----------------------------------------------------------------------
do
    for id = 1, 151 do
        local okInst, p = pcall(BattleEngine.newPokemon, id, 50)
        ok(okInst and p ~= nil, "instantiate #" .. id .. " " .. (PokemonData.get(id) and PokemonData.get(id).name or "?"))
    end

    local matchups = {
        { 6, 9 }, { 150, 151 }, { 1, 4 }, { 25, 26 }, { 128, 143 }, { 94, 65 },
    }
    for _, match in ipairs(matchups) do
        local a = BattleEngine.newPokemon(match[1], 60)
        local b = BattleEngine.newPokemon(match[2], 60)
        local battle = BattleEngine.newBattle({ a }, { b }, { seed = 42, mode = "bot" })
        local turns = 0
        while not battle.over and turns < 300 do
            turns = turns + 1
            battle:runTurn({
                [1] = Bot.chooseMove(battle, 1),
                [2] = Bot.chooseMove(battle, 2),
            })
        end
        ok(battle.over, PokemonData.get(match[1]).name .. " vs " .. PokemonData.get(match[2]).name .. " completes in " .. turns .. " turns")
        ok(battle.winner ~= nil, "winner decided")
    end
end

----------------------------------------------------------------------
-- Team battle (switching + fainting)
----------------------------------------------------------------------
do
    local teamA = { BattleEngine.newPokemon(6, 50), BattleEngine.newPokemon(9, 50) }
    local teamB = { BattleEngine.newPokemon(1, 20) }
    local battle = BattleEngine.newBattle(teamA, teamB, { seed = 8, mode = "bot" })
    local turns = 0
    while not battle.over and turns < 100 do
        turns = turns + 1
        battle:runTurn({
            [1] = { type = "move", index = 1 },
            [2] = { type = "move", index = 1 },
        })
    end
    ok(battle.over, "team battle completes")
    eq(battle.winner, 1, "strong team wins")
end

----------------------------------------------------------------------
-- Practice bots
----------------------------------------------------------------------
do
    ok(Bot.count() >= 10, "at least 10 practice bots")
    for i = 1, Bot.count() do
        local def = Bot.get(i)
        ok(def.name ~= nil, "bot " .. i .. " has a name")
        local team = Bot.buildTeam(def)
        eq(#team, #def.team, "bot " .. def.name .. " team built with " .. #def.team .. " Pokemon")
        for _, p in ipairs(team) do
            ok(p.hp == p.maxHp, "bot Pokemon starts at full HP")
            ok(#p.moves >= 1, "bot Pokemon has moves")
        end
    end

    -- Bot.random never returns the excluded index
    local rng = PRNG.new(5)
    for _ = 1, 50 do
        local idx, _ = Bot.random(rng, 3)
        ok(idx ~= 3, "Bot.random excludes current")
    end

    -- full bot battle completes
    local def = Bot.get(1)
    local myTeam = { BattleEngine.newPokemon(6, 50), BattleEngine.newPokemon(9, 50), BattleEngine.newPokemon(3, 50) }
    local botTeam = Bot.buildTeam(def)
    local battle = BattleEngine.newBattle(myTeam, botTeam, { seed = 11, mode = "bot", nameA = "You", nameB = def.name })
    local turns = 0
    while not battle.over and turns < 300 do
        turns = turns + 1
        battle:runTurn({
            [1] = Bot.chooseMove(battle, 1),
            [2] = Bot.chooseMove(battle, 2),
        })
    end
    ok(battle.over, "bot battle completes")
    ok(battle.winner ~= nil, "bot battle has a winner")
end

----------------------------------------------------------------------
-- Serialization round-trip
----------------------------------------------------------------------
do
    local p = BattleEngine.newPokemon(25, 42, { nickname = "Sparky", moves = { "Thunderbolt", "QuickAttack" } })
    p.hp = 10
    local enc = Serializer.encodePokemon(p)
    eq(enc.id, 25, "serialize id")
    eq(enc.level, 42, "serialize level")
    eq(enc.nickname, "Sparky", "serialize nickname")
    eq(#enc.moves, 2, "serialize moves count")

    local dec = Serializer.decodePokemon(enc, BattleEngine)
    eq(dec.id, 25, "decode id")
    eq(dec.level, 42, "decode level")
    eq(dec.name, "Sparky", "decode nickname")
    eq(dec.moves[1].id, "Thunderbolt", "decode move 1")

    -- team round-trip
    local team = {
        BattleEngine.newPokemon(1, 100),
        BattleEngine.newPokemon(4, 100),
        BattleEngine.newPokemon(7, 100),
    }
    local encTeam = Serializer.encodeTeam(team)
    local decTeam = Serializer.decodeTeam(encTeam, BattleEngine)
    eq(#decTeam, 3, "team round-trip count")
    eq(decTeam[2].id, 4, "team round-trip member 2")
    eq(decTeam[3].moves[1].pp, decTeam[3].moves[1].maxPp, "decoded move pp full")
end

----------------------------------------------------------------------
-- Net protocol
----------------------------------------------------------------------
do
    local msg = Net.buildChallenge("Alice", "Bob", 6)
    local t, d, okDecode = Net.decode(msg)
    eq(t, Net.MSG.CHALLENGE, "net decode type")
    ok(okDecode, "net decode ok")
    eq(d.from, "Alice", "net challenge from")
    eq(d.to, "Bob", "net challenge to")

    local start = Net.buildStart("Alice", "Bob", 12345, { { id = 1, level = 5, moves = { "Tackle" } } })
    local t2, d2 = Net.decode(start)
    eq(t2, Net.MSG.START, "net start type")
    eq(d2.seed, 12345, "net start seed")

    local choice = Net.buildChoice("Alice", "Bob", 3, { type = "move", index = 2 })
    local t3, d3 = Net.decode(choice)
    eq(t3, Net.MSG.CHOICE, "net choice type")
    eq(d3.choice.index, 2, "net choice index")

    local _, _, ok3 = Net.decode("OTHER:stuff")
    ok(not ok3, "net rejects wrong prefix")

    local _, _, ok4 = Net.decode(Net.PREFIX .. ":{not json")
    ok(not ok4, "net rejects malformed json")

    local bad = Net.PREFIX .. ':{"t":"hello","v":999,"d":{}}'
    local _, _, ok5 = Net.decode(bad)
    ok(not ok5, "net rejects version mismatch")
end

----------------------------------------------------------------------
-- JSON
----------------------------------------------------------------------
do
    local enc = Json.encode({ a = 1, b = { 1, 2, 3 }, c = "hi", d = true, e = nil })
    local dec = Json.decode(enc)
    eq(dec.a, 1, "json number")
    eq(dec.b[2], 2, "json array")
    eq(dec.c, "hi", "json string")
    eq(dec.d, true, "json bool")
    eq(dec.e, nil, "json null omitted")

    local s = Json.encode({ text = 'a"b\\c\nd' })
    local d2 = Json.decode(s)
    eq(d2.text, 'a"b\\c\nd', "json escapes round-trip")

    local u = Json.decode('{"x":"\\u0041"}')
    eq(u.x, "A", "json unicode escape")
end

----------------------------------------------------------------------
-- PvP determinism: both clients simulate the same battle
----------------------------------------------------------------------
do
    local seed = 31337
    local teamA = { BattleEngine.newPokemon(6, 50), BattleEngine.newPokemon(25, 50) }
    local teamB = { BattleEngine.newPokemon(9, 50), BattleEngine.newPokemon(1, 50) }

    local snapshotA = Serializer.encodeTeam(teamA)
    local snapshotB = Serializer.encodeTeam(teamB)
    local client1 = BattleEngine.newBattle(
        Serializer.decodeTeam(snapshotA, BattleEngine),
        Serializer.decodeTeam(snapshotB, BattleEngine),
        { mode = "pvp", seed = seed })
    local client2 = BattleEngine.newBattle(
        Serializer.decodeTeam(snapshotA, BattleEngine),
        Serializer.decodeTeam(snapshotB, BattleEngine),
        { mode = "pvp", seed = seed })

    local choices = {
        { { type = "move", index = 1 }, { type = "move", index = 1 } },
        { { type = "move", index = 2 }, { type = "move", index = 2 } },
        { { type = "move", index = 1 }, { type = "move", index = 3 } },
    }
    local sameLogs = true
    for _, ch in ipairs(choices) do
        client1:runTurn(ch)
        client2:runTurn(ch)
        if #client1.log ~= #client2.log then sameLogs = false break end
        for i = 1, #client1.log do
            if client1.log[i] ~= client2.log[i] then sameLogs = false break end
        end
    end
    ok(sameLogs, "PvP: both clients produce identical logs")
    eq(client1.winner, client2.winner, "PvP: same winner on both clients")
end

----------------------------------------------------------------------
-- Stress: many AI battles complete without stalling or erroring
----------------------------------------------------------------------
do
    local stalls, errors, maxTurns = 0, 0, 0
    local rng = PRNG.new(777)
    for _ = 1, 200 do
        local idA = rng:nextInt(1, 151)
        local idB = rng:nextInt(1, 151)
        local ok, err = pcall(function()
            local a = BattleEngine.newPokemon(idA, rng:nextInt(5, 100))
            local b = BattleEngine.newPokemon(idB, rng:nextInt(5, 100))
            local battle = BattleEngine.newBattle({ a }, { b }, { seed = rng:nextInt(1, 2 ^ 31), mode = "bot" })
            local turns = 0
            while not battle.over and turns < 300 do
                turns = turns + 1
                battle:runTurn({
                    [1] = Bot.chooseMove(battle, 1),
                    [2] = Bot.chooseMove(battle, 2),
                })
            end
            if not battle.over then stalls = stalls + 1 end
            if turns > maxTurns then maxTurns = turns end
        end)
        if not ok then errors = errors + 1 end
    end
    eq(errors, 0, "stress: no errors in 200 AI battles")
    eq(stalls, 0, "stress: no stalled battles")
    ok(maxTurns <= BattleEngine.MAX_TURNS + 1, "stress: battles respect turn cap (max " .. maxTurns .. ")")

    -- 6v6 team battles
    local teamErrors = 0
    local rng2 = PRNG.new(555)
    for _ = 1, 30 do
        local ok = pcall(function()
            local teamA, teamB = {}, {}
            for j = 1, 6 do
                teamA[j] = BattleEngine.newPokemon(rng2:nextInt(1, 151), rng2:nextInt(20, 80))
                teamB[j] = BattleEngine.newPokemon(rng2:nextInt(1, 151), rng2:nextInt(20, 80))
            end
            local battle = BattleEngine.newBattle(teamA, teamB, { seed = rng2:nextInt(1, 2 ^ 31), mode = "bot" })
            local turns = 0
            while not battle.over and turns < 300 do
                turns = turns + 1
                battle:runTurn({
                    [1] = Bot.chooseMove(battle, 1),
                    [2] = Bot.chooseMove(battle, 2),
                })
            end
            ok(battle.over, "6v6 battle completes")
        end)
        if not ok then teamErrors = teamErrors + 1 end
    end
    eq(teamErrors, 0, "stress: 6v6 team battles complete")

    -- Struggle: a Pokemon with all PP exhausted still fights
    local solo = BattleEngine.newPokemon(11, 50) -- Metapod (only Harden)
    for _, m in ipairs(solo.moves) do m.pp = 0 end
    local foe = BattleEngine.newPokemon(16, 50)
    local bStr = BattleEngine.newBattle({ solo }, { foe }, { seed = 1 })
    bStr:useMove(1, 1)
    ok(true, "Struggle path does not error")
end

----------------------------------------------------------------------
-- Summary
----------------------------------------------------------------------
print("")
print(string.format("Tests: %d passed, %d failed", passed, failed))
_TEST_RESULT = { passed = passed, failed = failed, failures = failures }
if failed > 0 then
    print("Failures:")
    for _, f in ipairs(failures) do print("  - " .. f) end
end
-- only exit when running standalone (not embedded via lupa)
if not _LUPA and os and os.exit then
    os.exit(failed > 0 and 1 or 0)
end
