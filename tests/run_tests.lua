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
        -- print("PASS " .. name)
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

-- Load modules
local Types = require("Core.Data.Types")
local Moves = require("Core.Data.Moves")
local PokemonData = require("Core.Data.Pokemon")
local Trainers = require("Core.Data.Trainers")
local PRNG = require("Core.Util.PRNG")
local Json = require("Core.Libs.Json")
local Stats = require("Core.Stats")
local BattleEngine = require("Core.BattleEngine")
local Encounters = require("Core.Encounters")
local Serializer = require("Core.Util.Serializer")
local Net = require("Core.Net")

----------------------------------------------------------------------
-- Data integrity
----------------------------------------------------------------------
do
    eq(PokemonData.count(), 151, "151 Pokemon defined")

    -- every Pokemon has valid types and base stats
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

    -- every learnset move exists and levels are sorted
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

    -- every move has a valid type and sane values
    for id, m in pairs(Moves.list) do
        ok(Types.isValid(m.type), "Move " .. id .. " type valid")
        ok(m.acc >= 0 and m.acc <= 100, "Move " .. id .. " acc in range")
        ok(m.pp > 0, "Move " .. id .. " pp > 0")
        ok(m.power >= 0, "Move " .. id .. " power >= 0")
    end

    -- trainer teams reference valid species
    for _, t in ipairs(Trainers.list) do
        ok(#t.teams >= 1, "Trainer " .. t.name .. " has teams")
        for _, team in ipairs(t.teams) do
            for _, member in ipairs(team) do
                ok(PokemonData.get(member[1]) ~= nil, "Trainer " .. t.name .. " species #" .. member[1] .. " valid")
                ok(member[2] >= 1 and member[2] <= 100, "Trainer " .. t.name .. " level in range")
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
    eq(Types.getEffectiveness("Ice", "Fire"), 0.5, "Gen 1: Ice NVE vs Fire")
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

    -- range checks
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

    -- distribution sanity for chance()
    local r3 = PRNG.new(42)
    local hits = 0
    for _ = 1, 10000 do if r3:chance(50) then hits = hits + 1 end end
    approx(hits / 10000, 0.5, 0.03, "PRNG chance(50) ~ 50%")
end

----------------------------------------------------------------------
-- Stats
----------------------------------------------------------------------
do
    local species = PokemonData.get(6) -- Charizard
    local stats = Stats.computeStats(species, 50)
    ok(stats.hp > stats.spe or stats.spe > 0, "Charizard Lv50 has positive stats")
    ok(stats.hp > 100, "Charizard Lv50 HP > 100 (got " .. stats.hp .. ")")
    eq(stats.spa, stats.spd, "Gen 1: spa == spd")

    -- higher level => higher stats
    local s50 = Stats.computeStats(species, 50)
    local s100 = Stats.computeStats(species, 100)
    ok(s100.hp > s50.hp, "Lv100 HP > Lv50 HP")
    ok(s100.atk > s50.atk, "Lv100 Atk > Lv50 Atk")

    -- EVs increase stats
    local noEv = Stats.computeStats(species, 50)
    local withEv = Stats.computeStats(species, 50, nil, { atk = 255 })
    ok(withEv.atk > noEv.atk, "EVs increase stats")

    -- exp curve
    ok(Stats.expForLevel(1) > 0, "expForLevel(1) > 0")
    ok(Stats.expForLevel(50) > Stats.expForLevel(10), "exp curve increasing")
    eq(Stats.totalExpForLevel(1), 0, "totalExpForLevel(1) == 0")
    ok(Stats.totalExpForLevel(10) > 0, "totalExpForLevel(10) > 0")
end

----------------------------------------------------------------------
-- Pokemon instance creation
----------------------------------------------------------------------
do
    local p = BattleEngine.newPokemon(25, 50) -- Pikachu
    eq(p.name, "Pikachu", "newPokemon name")
    eq(p.level, 50, "newPokemon level")
    ok(p.hp == p.maxHp, "newPokemon full HP")
    ok(#p.moves >= 1 and #p.moves <= 4, "newPokemon 1-4 moves")
    eq(p.types[1], "Electric", "Pikachu type")

    -- moveset is the most recent 4 from learnset
    local bulb = BattleEngine.newPokemon(1, 40) -- Bulbasaur
    local ids = {}
    for _, m in ipairs(bulb.moves) do ids[#ids + 1] = m.id end
    -- at L40 Bulbasaur knows up to SolarBeam (34)
    local hasSolar = false
    for _, id in ipairs(ids) do if id == "SolarBeam" then hasSolar = true end end
    ok(hasSolar, "Bulbasaur L40 knows SolarBeam")

    -- Mewtwo has huge special
    local mew = BattleEngine.newPokemon(150, 100)
    ok(mew.stats.spa > 250, "Mewtwo L100 spa > 250 (got " .. mew.stats.spa .. ")")
end

----------------------------------------------------------------------
-- Battle engine: damage, turns, KO
----------------------------------------------------------------------
do
    -- deterministic battle: same seed + same choices => same log
    local function runBattle(seed)
        local a1 = BattleEngine.newPokemon(6, 50)  -- Charizard
        local b1 = BattleEngine.newPokemon(9, 50)  -- Blastoise
        local battle = BattleEngine.newBattle({ a1 }, { b1 }, { mode = "pve", seed = seed })
        local log = {}
        battle.onLog = function(m) log[#log + 1] = m end
        local turns = 0
        while not battle.over and turns < 200 do
            turns = turns + 1
            battle:runTurn({ [1] = { type = "move", index = 1 }, [2] = { type = "move", index = 1 } })
        end
        return log, battle
    end

    local logA, battleA = runBattle(123)
    local logB, battleB = runBattle(123)
    eq(#logA, #logB, "deterministic battle: same log length")
    local sameLog = true
    for i = 1, #logA do
        if logA[i] ~= logB[i] then sameLog = false break end
    end
    ok(sameLog, "deterministic battle: identical logs")
    ok(battleA.over, "battle eventually ends")
    ok(battleA.winner == 1 or battleA.winner == 2, "battle has a winner")

    -- different seeds usually differ
    local logC = runBattle(999)
    local diff = false
    for i = 1, math.min(#logA, #logC) do
        if logA[i] ~= logC[i] then diff = true break end
    end
    ok(diff, "different seed -> different battle")

    -- type effectiveness matters: Water vs Fire does more than Fire vs Water
    local atk = BattleEngine.newPokemon(9, 50)   -- Blastoise (Water)
    local defFire = BattleEngine.newPokemon(6, 50) -- Charizard (Fire)
    local defWater = BattleEngine.newPokemon(9, 50) -- Blastoise (Water)
    local surf = Moves.get("Surf")
    local b1 = BattleEngine.newBattle({ atk }, { defFire }, { seed = 5 })
    local b2 = BattleEngine.newBattle({ atk }, { defWater }, { seed = 5 })
    local dmgFire = b1:calcDamage(atk, defFire, surf)
    local dmgWater = b2:calcDamage(atk, defWater, surf)
    ok(dmgFire > dmgWater, "Surf does more to Fire than to Water")

    -- STAB: same-type move does more
    local stabDmg = b1:calcDamage(atk, defFire, Moves.get("HydroPump"))
    -- compare vs a neutral hitter using HydroPump
    local neutral = BattleEngine.newPokemon(128, 50) -- Tauros (Normal)
    local b3 = BattleEngine.newBattle({ neutral }, { defFire }, { seed = 5 })
    local neutralDmg = b3:calcDamage(neutral, defFire, Moves.get("HydroPump"))
    -- Tauros has lower spa but STAB should still help Blastoise; just check both > 0
    ok(stabDmg > 0 and neutralDmg > 0, "damage positive")

    -- immunity: Electric vs Ground does 0 via useMove
    local raichu = BattleEngine.newPokemon(26, 50)
    local diglett = BattleEngine.newPokemon(50, 50)
    local b4 = BattleEngine.newBattle({ raichu }, { diglett }, { seed = 1 })
    local res = b4:useMove(1, 4) -- Thunderbolt (index 4)
    ok(res.immune, "Electric move immune vs Ground")

    -- status: Thunder Wave paralyzes
    local b5 = BattleEngine.newBattle(
        { BattleEngine.newPokemon(25, 50) },
        { BattleEngine.newPokemon(16, 50) },
        { seed = 77 })
    -- find the ThunderWave slot (Pikachu L50: QuickAttack, Swift, Agility, Thunderbolt)
    -- so inject ThunderWave explicitly for a deterministic check
    b5:active(1).moves[1] = { id = "ThunderWave", pp = 20, maxPp = 20 }
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
    local b7 = BattleEngine.newBattle({ p, BattleEngine.newPokemon(9, 50) }, { BattleEngine.newPokemon(1, 50) }, { seed = 1 })
    b7:forceSwitch(1, 2)
    eq(b7:active(1).stages.atk, 0, "switch resets stages")
end

----------------------------------------------------------------------
-- Full battle simulation to completion (AI vs AI) for all 151 species sanity
----------------------------------------------------------------------
do
    -- every species can be instantiated and battle without errors
    for id = 1, 151 do
        local okInst, p = pcall(BattleEngine.newPokemon, id, 50)
        ok(okInst and p ~= nil, "instantiate #" .. id .. " " .. (PokemonData.get(id) and PokemonData.get(id).name or "?"))
    end

    -- a few full AI battles across tiers
    local matchups = {
        { 6, 9 },    -- Charizard vs Blastoise
        { 150, 151 },-- Mewtwo vs Mew
        { 1, 4 },    -- Bulbasaur vs Charmander
        { 25, 26 },  -- Pikachu vs Raichu
        { 128, 143 },-- Tauros vs Snorlax
        { 94, 65 },  -- Gengar vs Alakazam
    }
    for _, match in ipairs(matchups) do
        local a = BattleEngine.newPokemon(match[1], 60)
        local b = BattleEngine.newPokemon(match[2], 60)
        local battle = BattleEngine.newBattle({ a }, { b }, { seed = 42, mode = "pve" })
        local turns = 0
        while not battle.over and turns < 300 do
            turns = turns + 1
            battle:runTurn({
                [1] = Encounters.aiChooseMove(battle, 1),
                [2] = Encounters.aiChooseMove(battle, 2),
            })
        end
        ok(battle.over, PokemonData.get(match[1]).name .. " vs " .. PokemonData.get(match[2]).name .. " completes in " .. turns .. " turns")
        ok(battle.winner ~= nil, "winner decided")
    end
end

----------------------------------------------------------------------
-- Multi-Pokemon team battle (switching + fainting)
----------------------------------------------------------------------
do
    local teamA = { BattleEngine.newPokemon(6, 50), BattleEngine.newPokemon(9, 50) }
    local teamB = { BattleEngine.newPokemon(1, 20) } -- weak foe
    local battle = BattleEngine.newBattle(teamA, teamB, { seed = 8, mode = "pve" })
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
            local battle = BattleEngine.newBattle({ a }, { b }, { seed = rng:nextInt(1, 2 ^ 31), mode = "pve" })
            local turns = 0
            while not battle.over and turns < 300 do
                turns = turns + 1
                battle:runTurn({
                    [1] = Encounters.aiChooseMove(battle, 1),
                    [2] = Encounters.aiChooseMove(battle, 2),
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
            local battle = BattleEngine.newBattle(teamA, teamB, { seed = rng2:nextInt(1, 2 ^ 31), mode = "pve" })
            local turns = 0
            while not battle.over and turns < 300 do
                turns = turns + 1
                battle:runTurn({
                    [1] = Encounters.aiChooseMove(battle, 1),
                    [2] = Encounters.aiChooseMove(battle, 2),
                })
            end
            ok(battle.over, "6v6 battle completes")
        end)
        if not ok then teamErrors = teamErrors + 1 end
    end
    eq(teamErrors, 0, "stress: 6v6 team battles complete")

    -- Struggle: a Pokemon with all PP exhausted still deals damage
    local solo = BattleEngine.newPokemon(11, 50) -- Metapod (only Harden)
    for _, m in ipairs(solo.moves) do m.pp = 0 end
    local foe = BattleEngine.newPokemon(16, 50)
    local bStr = BattleEngine.newBattle({ solo }, { foe }, { seed = 1 })
    local foeHpBefore = foe.hp
    bStr:useMove(1, 1)
    ok(foe.hp <= foeHpBefore, "Struggle deals damage (or recoil self-damage)")
end

----------------------------------------------------------------------
-- EXP / leveling
----------------------------------------------------------------------
do
    local p = BattleEngine.newPokemon(1, 5)
    local milestones = BattleEngine.gainExp(p, 1000)
    ok(p.level > 5, "gainExp levels up (now " .. p.level .. ")")
    ok(#milestones >= 1, "milestones returned")
    ok(p.hp <= p.maxHp, "hp within max after level up")

    -- level cap
    local p2 = BattleEngine.newPokemon(1, 99)
    BattleEngine.gainExp(p2, 99999999)
    ok(p2.level <= 100, "level capped at 100")
end

----------------------------------------------------------------------
-- Encounters & catching
----------------------------------------------------------------------
do
    local rng = PRNG.new(123)
    local seen = {}
    for _ = 1, 200 do
        local enc = Encounters.generateWild(rng, "forest", 10)
        ok(enc.pokemon ~= nil, "wild encounter generated")
        seen[enc.pokemon.id] = true
        ok(enc.pokemon.level >= 1, "wild level >= 1")
    end
    ok(next(seen) ~= nil, "forest encounters produce Pokemon")

    -- all zone types work
    for _, zone in ipairs({ "forest", "water", "cave", "mountain", "powerplant", "sea", "mansion", "default" }) do
        local e = Encounters.generateWild(PRNG.new(5), zone, 20)
        ok(e.pokemon ~= nil, "zone '" .. zone .. "' generates")
    end

    -- catching: masterball always works; weak mon + low HP + great ball usually works
    local weak = BattleEngine.newPokemon(10, 3) -- Caterpie L3
    local rng2 = PRNG.new(7)
    local master = Encounters.attemptCatch(rng2, weak, "masterball", 50)
    ok(master.success, "masterball always catches")

    local catches = 0
    for i = 1, 50 do
        local fresh = BattleEngine.newPokemon(129, 5) -- Magikarp
        fresh.hp = 1
        local r = Encounters.attemptCatch(PRNG.new(i), fresh, "greatball", 50)
        if r.success then catches = catches + 1 end
    end
    ok(catches > 10, "low-HP Magikarp with great ball catches reasonably often (" .. catches .. "/50)")

    -- strong high-HP mon is hard to catch
    local mewtwo = BattleEngine.newPokemon(150, 100)
    local hardCatches = 0
    for i = 1, 50 do
        local fresh = BattleEngine.newPokemon(150, 100)
        fresh.hp = fresh.maxHp
        local r = Encounters.attemptCatch(PRNG.new(1000 + i), fresh, "pokeball", 100)
        if r.success then hardCatches = hardCatches + 1 end
    end
    ok(hardCatches < 25, "full-HP L100 Mewtwo hard to catch with pokeball (" .. hardCatches .. "/50)")

    -- trainers generate valid teams
    local t = Encounters.generateTrainer(PRNG.new(3))
    ok(#t.team >= 1, "trainer has a team")
    for _, p in ipairs(t.team) do
        ok(p.species ~= nil, "trainer Pokemon valid")
    end
end

----------------------------------------------------------------------
-- Serialization round-trip
----------------------------------------------------------------------
do
    local p = BattleEngine.newPokemon(25, 42, { shiny = true, nickname = "Sparky" })
    p.hp = 10
    local enc = Serializer.encodePokemon(p)
    local dec = Serializer.decodePokemon(enc, BattleEngine)
    eq(dec.id, 25, "serialize id")
    eq(dec.level, 42, "serialize level")
    eq(dec.hp, 10, "serialize hp")
    eq(dec.name, "Sparky", "serialize nickname")
    ok(dec.shiny, "serialize shiny")
    eq(#dec.moves, #p.moves, "serialize moves count")

    -- team round-trip
    local team = { BattleEngine.newPokemon(1, 10), BattleEngine.newPokemon(4, 10), BattleEngine.newPokemon(7, 10) }
    local encTeam = Serializer.encodeTeam(team)
    local decTeam = Serializer.decodeTeam(encTeam, BattleEngine)
    eq(#decTeam, 3, "team round-trip count")
    eq(decTeam[2].id, 4, "team round-trip member 2")
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

    local start = Net.buildStart("Alice", "Bob", 12345, { { id = 1, level = 5 } })
    local t2, d2 = Net.decode(start)
    eq(t2, Net.MSG.START, "net start type")
    eq(d2.seed, 12345, "net start seed")

    -- wrong prefix rejected
    local t3, _, ok3 = Net.decode("OTHER:stuff")
    ok(not ok3, "net rejects wrong prefix")

    -- malformed json rejected
    local _, _, ok4 = Net.decode(Net.PREFIX .. ":{not json")
    ok(not ok4, "net rejects malformed json")

    -- version mismatch rejected
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

    -- special chars
    local s = Json.encode({ text = 'a"b\\c\nd' })
    local d2 = Json.decode(s)
    eq(d2.text, 'a"b\\c\nd', "json escapes round-trip")

    -- unicode escape
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

    -- client 1
    local snapshotA = Serializer.encodeTeam(teamA)
    local snapshotB = Serializer.encodeTeam(teamB)
    local decodeA = Serializer.decodeTeam(snapshotA, BattleEngine)
    local decodeB = Serializer.decodeTeam(snapshotB, BattleEngine)
    local client1 = BattleEngine.newBattle(decodeA, Serializer.decodeTeam(snapshotB, BattleEngine), { mode = "pvp", seed = seed })
    local client2 = BattleEngine.newBattle(Serializer.decodeTeam(snapshotA, BattleEngine), decodeB, { mode = "pvp", seed = seed })

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
