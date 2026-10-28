-- Integration / logical test suite for the Showdown Clone addon.
-- Complements run_tests.lua with end-to-end flows.

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
-- 1. Data integrity cross-references
----------------------------------------------------------------------
do
    local seen = {}
    for id, p in pairs(PokemonData.list) do
        ok(id >= 1 and id <= 151, "Species id " .. id .. " in range 1..151")
        ok(not seen[id], "Species id " .. id .. " not duplicated")
        seen[id] = true
    end
    for id = 1, 151 do
        ok(seen[id], "Species #" .. id .. " exists (no gaps)")
    end
    eq(PokemonData.count(), 151, "Exactly 151 species")

    for id, p in pairs(PokemonData.list) do
        eq(PokemonData.getByName(p.name), id, "byName('" .. p.name .. "') == " .. id)
        eq(PokemonData.getByName(p.name:lower()), id, "byName lowercase '" .. p.name .. "'")
    end
    eq(PokemonData.getByName("nonexistent"), nil, "byName unknown returns nil")
    eq(PokemonData.get(0), nil, "get(0) returns nil")
    eq(PokemonData.get(152), nil, "get(152) returns nil")
    eq(PokemonData.get(-1), nil, "get(-1) returns nil")

    for id, p in pairs(PokemonData.list) do
        for _, entry in ipairs(p.learnset) do
            local lv, moveId = entry[1], entry[2]
            ok(Moves.exists(moveId), p.name .. " learnset move '" .. tostring(moveId) .. "' exists in Moves")
        end
    end

    for _, def in ipairs(Bot.TEAMS) do
        for _, member in ipairs(def.team) do
            if member.moves then
                for _, mv in ipairs(member.moves) do
                    ok(Moves.exists(mv), "Bot " .. def.name .. " custom move '" .. tostring(mv) .. "' exists")
                end
            end
        end
    end

    for id, m in pairs(Moves.list) do
        ok(Types.isValid(m.type), "Move " .. id .. " has valid type '" .. tostring(m.type) .. "'")
        if not m.cat then
            eq(Types.categoryFor(m.type), Types.CATEGORIES[m.type],
                "Move " .. id .. " category matches type " .. m.type)
        else
            ok(m.cat == "physical" or m.cat == "special" or m.cat == "status",
                "Move " .. id .. " cat is valid ('" .. tostring(m.cat) .. "')")
        end
        ok(m.pp > 0 and m.pp <= 40, "Move " .. id .. " pp in 1..40 (got " .. tostring(m.pp) .. ")")
        ok(m.acc >= 0 and m.acc <= 100, "Move " .. id .. " acc in 0..100 (got " .. tostring(m.acc) .. ")")
        if m.power > 0 then
            ok(m.power <= 250, "Move " .. id .. " power <= 250 (got " .. m.power .. ")")
        end
        if m.cat == "status" then
            eq(m.power, 0, "Move " .. id .. " status move has power 0")
        end
        if m.power > 0 then
            ok(m.cat ~= "status", "Move " .. id .. " damaging move is not status cat")
        end
    end

    for id, p in pairs(PokemonData.list) do
        eq(p.base.spa, p.base.spd, p.name .. " Gen 1 spa == spd")
    end

    for id, p in pairs(PokemonData.list) do
        for _, k in ipairs({ "hp", "atk", "def", "spa", "spd", "spe" }) do
            ok(p.base[k] >= 1 and p.base[k] <= 255,
                p.name .. " base." .. k .. " in 1..255 (got " .. p.base[k] .. ")")
        end
    end

    for id, p in pairs(PokemonData.list) do
        for _, t in ipairs(p.types) do
            ok(t ~= "Fairy" and t ~= "Steel" and t ~= "Dark",
                p.name .. " has no Gen 2+ type (has " .. t .. ")")
        end
    end

    for _, atk in ipairs(Types.list) do
        for _, def in ipairs(Types.list) do
            local mult = Types.getEffectiveness(atk, def)
            ok(mult == 0 or mult == 0.5 or mult == 1 or mult == 2,
                "Chart " .. atk .. " vs " .. def .. " = " .. tostring(mult) .. " is valid")
        end
    end

    eq(Types.getEffectivenessVs("Ice", "Grass", "Flying"), 4, "Ice vs Grass/Flying = 4x")
    eq(Types.getEffectivenessVs("Electric", "Water", "Flying"), 4, "Electric vs Water/Flying = 4x")
    eq(Types.getEffectivenessVs("Grass", "Water", "Ground"), 4, "Grass vs Water/Ground = 4x")
    eq(Types.getEffectivenessVs("Water", "Fire", "Ground"), 4, "Water vs Fire/Ground = 4x")
    eq(Types.getEffectivenessVs("Electric", "Water", "Ground"), 0, "Electric vs Water/Ground = 0x")
    eq(Types.getEffectivenessVs("Fire", "Water", "Rock"), 0.25, "Fire vs Water/Rock = 0.25x")
    eq(Types.getEffectivenessVs("Fire", "Fire", "Fire"), 0.5, "Fire vs Fire/Fire = 0.5 (not 0.25)")
end

----------------------------------------------------------------------
-- 2. Serializer round-trip
----------------------------------------------------------------------
do
    local team = {}
    team[1] = BattleEngine.newPokemon(1, 100, { moves = { "Tackle", "Growl", "LeechSeed", "VineWhip" } })
    team[2] = BattleEngine.newPokemon(4, 50, { moves = { "Scratch2", "Ember" } })
    team[3] = BattleEngine.newPokemon(150, 100)
    team[4] = BattleEngine.newPokemon(113, 75, { moves = { "SoftBoiled", "ThunderWave", "IceBeam", "Thunderbolt" }, nickname = "Blissey" })

    local encoded = Serializer.encodeTeam(team)
    eq(#encoded, 4, "Encoded team has 4 entries")

    for i, ep in ipairs(encoded) do
        eq(type(ep.id), "number", "Encoded[" .. i .. "].id is number")
        eq(type(ep.level), "number", "Encoded[" .. i .. "].level is number")
        eq(type(ep.moves), "table", "Encoded[" .. i .. "].moves is table")
        for j, mv in ipairs(ep.moves) do
            eq(type(mv), "string", "Encoded[" .. i .. "].moves[" .. j .. "] is string")
        end
    end

    local decoded = Serializer.decodeTeam(encoded, BattleEngine)
    eq(#decoded, 4, "Decoded team has 4 entries")

    for i = 1, 4 do
        eq(decoded[i].id, team[i].id, "Round-trip team[" .. i .. "].id")
        eq(decoded[i].level, team[i].level, "Round-trip team[" .. i .. "].level")
        eq(#decoded[i].moves, #team[i].moves, "Round-trip team[" .. i .. "] move count")
        for j = 1, #team[i].moves do
            eq(decoded[i].moves[j].id, team[i].moves[j].id, "Round-trip team[" .. i .. "] move[" .. j .. "]")
        end
        eq(decoded[i].maxHp, team[i].maxHp, "Round-trip team[" .. i .. "].maxHp")
        eq(decoded[i].hp, team[i].hp, "Round-trip team[" .. i .. "].hp")
    end

    eq(decoded[4].nickname, "Blissey", "Nickname round-trip")
    local encodedNoNick = Serializer.encodePokemon(BattleEngine.newPokemon(25, 50))
    eq(encodedNoNick.nickname, nil, "Same-name nickname is not serialized")

    local jsonStr = Json.encode(encoded)
    local jsonDecoded = Json.decode(jsonStr)
    eq(#jsonDecoded, 4, "JSON round-trip team count")
    eq(jsonDecoded[1].id, 1, "JSON round-trip team[1].id")
    eq(jsonDecoded[4].nickname, "Blissey", "JSON round-trip nickname")
    local jsonTeam = Serializer.decodeTeam(jsonDecoded, BattleEngine)
    eq(jsonTeam[1].id, 1, "JSON->decode team[1].id")
    eq(jsonTeam[1].maxHp, team[1].maxHp, "JSON->decode team[1].maxHp")

    local emptyEnc = Serializer.encodeTeam({})
    eq(#emptyEnc, 0, "Empty team encodes to empty list")
    local emptyDec = Serializer.decodeTeam(emptyEnc, BattleEngine)
    eq(#emptyDec, 0, "Empty team decodes to empty list")
end

----------------------------------------------------------------------
-- 3. Full bot battles
----------------------------------------------------------------------
do
    local playerTeam = {
        BattleEngine.newPokemon(6, 100),
        BattleEngine.newPokemon(9, 100),
        BattleEngine.newPokemon(3, 100),
        BattleEngine.newPokemon(59, 100),
        BattleEngine.newPokemon(68, 100),
        BattleEngine.newPokemon(149, 100),
    }

    for botIdx, def in ipairs(Bot.TEAMS) do
        local botTeam = Bot.buildTeam(def)
        local seed = botIdx * 1000 + 42
        local battle = BattleEngine.newBattle(playerTeam, botTeam, {
            mode = "bot", seed = seed,
            nameA = "Player", nameB = def.name,
        })
        local turns = 0
        local okRun = pcall(function()
            while not battle.over and turns < 300 do
                turns = turns + 1
                battle:runTurn({
                    [1] = Bot.chooseMove(battle, 1),
                    [2] = Bot.chooseMove(battle, 2),
                })
            end
        end)
        ok(okRun, "Bot battle vs " .. def.name .. " completes without error")
        ok(battle.over, "Bot battle vs " .. def.name .. " ends (turns=" .. turns .. ")")
        ok(battle.winner == 1 or battle.winner == 2 or battle.winner == nil,
            "Bot battle vs " .. def.name .. " has valid winner")
        ok(turns <= BattleEngine.MAX_TURNS + 1,
            "Bot battle vs " .. def.name .. " respects turn cap (turns=" .. turns .. ")")
    end

    eq(Bot.get(1), Bot.TEAMS[1], "Bot.get(1) == TEAMS[1]")
    eq(Bot.get(#Bot.TEAMS), Bot.TEAMS[#Bot.TEAMS], "Bot.get(n) == TEAMS[n]")
    eq(Bot.get(#Bot.TEAMS + 1), Bot.TEAMS[1], "Bot.get(n+1) wraps to TEAMS[1]")
    eq(Bot.get(0), Bot.TEAMS[#Bot.TEAMS], "Bot.get(0) wraps to TEAMS[n]")
    eq(Bot.count(), #Bot.TEAMS, "Bot.count() == #TEAMS")

    local rng = PRNG.new(777)
    for _ = 1, 50 do
        local idx, bdef = Bot.random(rng, 3)
        ok(idx >= 1 and idx <= #Bot.TEAMS, "Bot.random returns valid index")
        ok(idx ~= 3, "Bot.random excludes requested index")
        ok(bdef == Bot.TEAMS[idx], "Bot.random returns matching def")
    end
end

----------------------------------------------------------------------
-- 4. PvP determinism
----------------------------------------------------------------------
do
    local function buildTeams()
        local t1 = {
            BattleEngine.newPokemon(25, 100, { moves = { "Thunderbolt", "ThunderWave", "QuickAttack", "BodySlam" } }),
            BattleEngine.newPokemon(6, 100, { moves = { "Flamethrower", "Slash", "Growl", "Leer" } }),
        }
        local t2 = {
            BattleEngine.newPokemon(9, 100, { moves = { "HydroPump", "Blizzard", "Tackle", "Withdraw" } }),
            BattleEngine.newPokemon(68, 100, { moves = { "KarateChop", "SeismicToss", "Leer", "LowKick" } }),
        }
        return t1, t2
    end

    local seed = 123456
    local teamA1, teamB1 = buildTeams()
    local battleA = BattleEngine.newBattle(teamA1, teamB1, { mode = "pvp", seed = seed })
    local teamA2, teamB2 = buildTeams()
    local battleB = BattleEngine.newBattle(teamA2, teamB2, { mode = "pvp", seed = seed })

    local rng = PRNG.new(999)
    local allSame = true
    for turn = 1, 20 do
        if battleA.over or battleB.over then break end
        local choice1 = { type = "move", index = rng:nextInt(1, 4) }
        local choice2 = { type = "move", index = rng:nextInt(1, 4) }
        battleA:runTurn({ [1] = choice1, [2] = choice2 })
        battleB:runTurn({ [1] = choice1, [2] = choice2 })
        for side = 1, 2 do
            for pi = 1, #battleA.sides[side].team do
                local pa = battleA.sides[side].team[pi]
                local pb = battleB.sides[side].team[pi]
                if pa.hp ~= pb.hp then allSame = false end
                if pa.status ~= pb.status then allSame = false end
                if pa.fainted ~= pb.fainted then allSame = false end
            end
            if battleA.sides[side].active ~= battleB.sides[side].active then allSame = false end
        end
        if battleA.over ~= battleB.over then allSame = false end
        if battleA.winner ~= battleB.winner then allSame = false end
    end
    ok(allSame, "PvP determinism: same seed + same choices = identical state after 20 turns")
    eq(battleA.winner, battleB.winner, "PvP determinism: same winner")
    eq(battleA.turn, battleB.turn, "PvP determinism: same turn count")

    local teamC1, teamD1 = buildTeams()
    local battleC = BattleEngine.newBattle(teamC1, teamD1, { mode = "pvp", seed = 111 })
    local teamC2, teamD2 = buildTeams()
    local battleD = BattleEngine.newBattle(teamC2, teamD2, { mode = "pvp", seed = 222 })
    local rng2 = PRNG.new(999)
    local diverged = false
    for turn = 1, 10 do
        if battleC.over or battleD.over then break end
        local choice1 = { type = "move", index = rng2:nextInt(1, 4) }
        local choice2 = { type = "move", index = rng2:nextInt(1, 4) }
        battleC:runTurn({ [1] = choice1, [2] = choice2 })
        battleD:runTurn({ [1] = choice1, [2] = choice2 })
        for side = 1, 2 do
            for pi = 1, #battleC.sides[side].team do
                if battleC.sides[side].team[pi].hp ~= battleD.sides[side].team[pi].hp then
                    diverged = true
                end
            end
        end
    end
    ok(diverged, "Different seeds produce different battle outcomes")
end

----------------------------------------------------------------------
-- 5. PvP message flow simulation
----------------------------------------------------------------------
do
    local aliceTeam = Serializer.encodeTeam({
        BattleEngine.newPokemon(1, 100, { moves = { "Tackle", "Growl" } }),
        BattleEngine.newPokemon(4, 100, { moves = { "Scratch2", "Ember" } }),
    })
    local challengeMsg = Net.buildChallenge("Alice", "Bob", #aliceTeam)

    local msgType, data, decodeOk = Net.decode(challengeMsg)
    eq(decodeOk, true, "PvP: challenge message decodes")
    eq(msgType, Net.MSG.CHALLENGE, "PvP: message type is CHALLENGE")
    eq(data.from, "Alice", "PvP: challenge from Alice")
    eq(data.to, "Bob", "PvP: challenge to Bob")
    eq(data.teamSize, 2, "PvP: challenge teamSize = 2")

    local acceptMsg = Net.buildChallengeResponse("Bob", "Alice", true)
    local respType, respData, respOk = Net.decode(acceptMsg)
    eq(respOk, true, "PvP: accept message decodes")
    eq(respType, Net.MSG.CHALLENGE_RESP, "PvP: response type is CHALLENGE_RESP")
    eq(respData.accepted, true, "PvP: accepted = true")

    local seed = 987654
    local startMsg = Net.buildStart("Alice", "Bob", seed, aliceTeam)
    local startType, startData, startOk = Net.decode(startMsg)
    eq(startOk, true, "PvP: start message decodes")
    eq(startType, Net.MSG.START, "PvP: start type is START")
    eq(startData.seed, seed, "PvP: start seed matches")
    eq(#startData.team, 2, "PvP: start team has 2 Pokemon")

    local aliceDecodedTeam = Serializer.decodeTeam(startData.team, BattleEngine)
    eq(#aliceDecodedTeam, 2, "PvP: Bob decodes Alice's team (2 Pokemon)")
    eq(aliceDecodedTeam[1].id, 1, "PvP: Alice's team[1] is Bulbasaur")

    local choiceMsg = Net.buildChoice("Alice", "Bob", 1, { type = "move", index = 1 })
    local choiceType, choiceData, choiceOk = Net.decode(choiceMsg)
    eq(choiceOk, true, "PvP: choice message decodes")
    eq(choiceType, Net.MSG.CHOICE, "PvP: choice type is CHOICE")
    eq(choiceData.choice.type, "move", "PvP: choice type is 'move'")
    eq(choiceData.choice.index, 1, "PvP: choice index is 1")
    eq(choiceData.turn, 1, "PvP: choice turn is 1")

    local resignMsg = Net.buildResign("Alice", "Bob")
    local resignType, resignData, resignOk = Net.decode(resignMsg)
    eq(resignOk, true, "PvP: resign message decodes")
    eq(resignType, Net.MSG.RESIGN, "PvP: resign type is RESIGN")

    local resultMsg = Net.buildResult("Alice", "Bob", 1, 15)
    local resultType, resultData, resultOk = Net.decode(resultMsg)
    eq(resultOk, true, "PvP: result message decodes")
    eq(resultType, Net.MSG.RESULT, "PvP: result type is RESULT")
    eq(resultData.winner, 1, "PvP: result winner is 1")
    eq(resultData.turns, 15, "PvP: result turns is 15")

    local declineMsg = Net.buildChallengeResponse("Bob", "Alice", false, "declined")
    local decType, decData, decOk = Net.decode(declineMsg)
    eq(decOk, true, "PvP: decline message decodes")
    eq(decData.accepted, false, "PvP: decline accepted=false")
    eq(decData.reason, "declined", "PvP: decline reason='declined'")

    local cancelMsg = Net.buildChallengeResponse("Alice", "Bob", false, "cancelled")
    local canType, canData, canOk = Net.decode(cancelMsg)
    eq(canOk, true, "PvP: cancel message decodes")
    eq(canData.reason, "cancelled", "PvP: cancel reason='cancelled'")

    local _, _, badOk = Net.decode("WRONGPREFIX:hello")
    eq(badOk, false, "PvP: wrong prefix rejected")
    local _, _, badOk2 = Net.decode("SHOWDOWN_CLONE:not json")
    eq(badOk2, false, "PvP: invalid JSON rejected")
    local _, _, badOk3 = Net.decode(nil)
    eq(badOk3, false, "PvP: nil message rejected")
    local _, _, badOk4 = Net.decode(42)
    eq(badOk4, false, "PvP: non-string message rejected")

    local oldVersionMsg = "SHOWDOWN_CLONE:" .. Json.encode({ t = "challenge", v = 999, d = {} })
    local _, _, verOk = Net.decode(oldVersionMsg)
    eq(verOk, false, "PvP: version mismatch rejected")
end

----------------------------------------------------------------------
-- 6. Edge cases
----------------------------------------------------------------------
do
    local emptyBattle = BattleEngine.newBattle({}, {}, { seed = 1 })
    local emptyOk = pcall(function()
        emptyBattle:runTurn({ [1] = { type = "move", index = 1 }, [2] = { type = "move", index = 1 } })
    end)
    ok(emptyOk, "Empty team battle does not crash")

    local p0 = BattleEngine.newPokemon(1, 0)
    eq(p0.level, 1, "Level 0 clamps to 1")
    local p999 = BattleEngine.newPokemon(1, 999)
    eq(p999.level, 100, "Level 999 clamps to 100")
    local pNeg = BattleEngine.newPokemon(1, -5)
    eq(pNeg.level, 1, "Level -5 clamps to 1")
    local pFrac = BattleEngine.newPokemon(1, 50.7)
    eq(pFrac.level, 50, "Level 50.7 floors to 50")
    local pNil = BattleEngine.newPokemon(1, nil)
    eq(pNil.level, 100, "Level nil defaults to 100")

    local unknownErr = pcall(BattleEngine.newPokemon, 999, 100)
    eq(unknownErr, false, "Unknown species 999 raises error")
    local unknownErr2 = pcall(BattleEngine.newPokemon, 0, 100)
    eq(unknownErr2, false, "Species 0 raises error")

    local pBadMove = BattleEngine.newPokemon(1, 100, { moves = { "NotAMove", "Tackle" } })
    eq(#pBadMove.moves, 1, "Invalid move id skipped, only Tackle kept")
    eq(pBadMove.moves[1].id, "Tackle", "Kept move is Tackle")

    local pAllBad = BattleEngine.newPokemon(1, 100, { moves = { "Foo", "Bar" } })
    eq(#pAllBad.moves, 1, "All invalid moves -> fallback to 1 move")
    eq(pAllBad.moves[1].id, "Tackle", "Fallback move is Tackle")

    local pDefault = BattleEngine.newPokemon(1, 100)
    ok(#pDefault.moves >= 1, "Default moves from learnset (got " .. #pDefault.moves .. ")")
    ok(#pDefault.moves <= 4, "Default moves capped at 4")

    local pMany = BattleEngine.newPokemon(1, 100, { moves = { "Tackle", "Growl", "LeechSeed", "VineWhip", "RazorLeaf" } })
    eq(#pMany.moves, 5, "5 explicit moves all kept (engine doesn't cap)")

    local statuses = { "burn", "poison", "paralysis", "sleep", "freeze", "confusion" }
    for _, st in ipairs(statuses) do
        local atk = BattleEngine.newPokemon(6, 100)
        local def = BattleEngine.newPokemon(9, 100)
        local b = BattleEngine.newBattle({ atk }, { def }, { seed = 42 })
        def.status = st
        if st == "sleep" then def.volatile.sleepTurns = 0; def.volatile.sleepMax = 1 end
        if st == "confusion" then def.volatile.confusionTurns = 0; def.volatile.confusionMax = 1 end
        local tickOk = pcall(function() b:applyResidual() end)
        ok(tickOk, "Residual tick with status " .. st .. " does not error")
        if st == "burn" or st == "poison" then
            ok(def.hp < def.maxHp, st .. " deals residual damage")
        end
    end

    local toxAtk = BattleEngine.newPokemon(6, 100)
    local toxDef = BattleEngine.newPokemon(9, 100)
    local toxBattle = BattleEngine.newBattle({ toxAtk }, { toxDef }, { seed = 1 })
    toxDef.status = "poison"
    toxDef.volatile.toxic = true
    local hpBefore = toxDef.hp
    toxBattle:applyResidual()
    local dmg1 = hpBefore - toxDef.hp
    hpBefore = toxDef.hp
    toxBattle:applyResidual()
    local dmg2 = hpBefore - toxDef.hp
    ok(dmg2 > dmg1, "Toxic poison escalates (dmg1=" .. dmg1 .. " dmg2=" .. dmg2 .. ")")

    local team = {
        BattleEngine.newPokemon(1, 100),
        BattleEngine.newPokemon(4, 100),
        BattleEngine.newPokemon(7, 100),
    }
    local foeTeam = { BattleEngine.newPokemon(25, 100) }
    local swBattle = BattleEngine.newBattle(team, foeTeam, { seed = 1 })
    eq(swBattle:forceSwitch(1, 2), true, "Switch to slot 2 works")
    eq(swBattle.sides[1].active, 2, "Active is now slot 2")
    eq(swBattle:forceSwitch(1, 2), false, "Switch to same slot fails")
    eq(swBattle:forceSwitch(1, 1), true, "Switch back to slot 1 works")
    eq(swBattle:forceSwitch(1, 0), false, "Switch to slot 0 fails")
    eq(swBattle:forceSwitch(1, 4), false, "Switch to slot 4 (out of range) fails")
    eq(swBattle:forceSwitch(1, -1), false, "Switch to slot -1 fails")

    team[2].fainted = true
    team[2].hp = 0
    eq(swBattle:forceSwitch(1, 2), false, "Switch to fainted Pokemon fails")

    team[1].fainted = true
    team[1].hp = 0
    eq(swBattle:autoSwitch(1), true, "autoSwitch finds non-fainted")
    eq(swBattle.sides[1].active, 3, "autoSwitch picked slot 3")

    team[3].fainted = true
    team[3].hp = 0
    eq(swBattle:autoSwitch(1), false, "autoSwitch returns false when all fainted")

    local ffBattle = BattleEngine.newBattle(
        { BattleEngine.newPokemon(1, 100) },
        { BattleEngine.newPokemon(4, 100) },
        { seed = 1 }
    )
    local ffOver = ffBattle:runTurn({ [1] = { type = "forfeit" } })
    eq(ffOver, true, "Forfeit ends battle")
    eq(ffBattle.winner, 2, "Forfeit: opponent wins")
    eq(ffBattle.over, true, "Forfeit: battle is over")

    local ppAtk = BattleEngine.newPokemon(1, 100, { moves = { "Tackle" } })
    ppAtk.moves[1].pp = 0
    local ppDef = BattleEngine.newPokemon(4, 100)
    local ppBattle = BattleEngine.newBattle({ ppAtk }, { ppDef }, { seed = 1 })
    ppBattle:useMove(1, 1)
    ok(ppDef.hp < ppDef.maxHp or ppAtk.hp < ppAtk.maxHp,
        "PP=0 uses Struggle and deals damage or recoil")

    local oneVone = BattleEngine.newBattle(
        { BattleEngine.newPokemon(1, 5) },
        { BattleEngine.newPokemon(4, 5) },
        { seed = 1 }
    )
    local ovTurns = 0
    while not oneVone.over and ovTurns < 50 do
        ovTurns = ovTurns + 1
        oneVone:runTurn({
            [1] = { type = "move", index = 1 },
            [2] = { type = "move", index = 1 },
        })
    end
    ok(oneVone.over, "1v1 battle ends when one faints")
    ok(oneVone.winner == 1 or oneVone.winner == 2, "1v1 battle has a winner")

    local hpBattle = BattleEngine.newBattle(
        { BattleEngine.newPokemon(150, 100) },
        { BattleEngine.newPokemon(1, 1) },
        { seed = 1 }
    )
    for _ = 1, 10 do
        if hpBattle.over then break end
        hpBattle:runTurn({
            [1] = { type = "move", index = 1 },
            [2] = { type = "move", index = 1 },
        })
        for side = 1, 2 do
            for _, p in ipairs(hpBattle.sides[side].team) do
                ok(p.hp >= 0, "HP never negative (side " .. side .. " " .. p.name .. " hp=" .. p.hp .. ")")
                ok(p.hp <= p.maxHp, "HP never exceeds maxHp (side " .. side .. " " .. p.name .. ")")
            end
        end
    end

    local stageBattle = BattleEngine.newBattle(
        { BattleEngine.newPokemon(1, 100, { moves = { "SwordsDance", "Harden", "Growl", "Tackle" } }) },
        { BattleEngine.newPokemon(4, 100, { moves = { "Leer", "SandAttack", "Scratch2", "Ember" } }) },
        { seed = 1 }
    )
    for _ = 1, 30 do
        if stageBattle.over then break end
        stageBattle:runTurn({
            [1] = { type = "move", index = 1 },
            [2] = { type = "move", index = 1 },
        })
        local p1 = stageBattle:active(1)
        local p2 = stageBattle:active(2)
        for _, p in ipairs({ p1, p2 }) do
            for stat, val in pairs(p.stages) do
                ok(val >= -6 and val <= 6,
                    "Stage " .. stat .. " in [-6,6] (got " .. val .. " for " .. p.name .. ")")
            end
        end
    end

    local stallA = BattleEngine.newPokemon(113, 100, { moves = { "SoftBoiled", "ThunderWave", "Minimize", "Harden" } })
    local stallB = BattleEngine.newPokemon(113, 100, { moves = { "SoftBoiled", "ThunderWave", "Minimize", "Harden" } })
    local stallBattle = BattleEngine.newBattle({ stallA }, { stallB }, { seed = 1 })
    local stallTurns = 0
    while not stallBattle.over and stallTurns < 250 do
        stallTurns = stallTurns + 1
        stallBattle:runTurn({
            [1] = { type = "move", index = 1 },
            [2] = { type = "move", index = 1 },
        })
    end
    ok(stallBattle.over, "Stall battle ends (turn cap or someone wins)")
    ok(stallTurns <= BattleEngine.MAX_TURNS + 1, "Stall battle respects turn cap (turns=" .. stallTurns .. ")")

    local fastP = BattleEngine.newPokemon(25, 100)
    local slowP = BattleEngine.newPokemon(143, 100)
    local spdBattle = BattleEngine.newBattle({ fastP }, { slowP }, { seed = 1 })
    eq(spdBattle:speedOf(fastP) > spdBattle:speedOf(slowP), true,
        "Speed order: Pikachu faster than Snorlax")

    slowP.status = "paralysis"
    local parSpe = spdBattle:speedOf(slowP)
    slowP.status = nil
    local normSpe = spdBattle:speedOf(slowP)
    ok(parSpe < normSpe, "Paralysis reduces speed")
    eq(parSpe, math.floor(normSpe / 4), "Paralysis quarters speed (Gen 1)")
end

----------------------------------------------------------------------
-- 7. Engine invariants across many random battles
----------------------------------------------------------------------
do
    local rng = PRNG.new(31337)
    local invariantErrors = 0
    local completedBattles = 0

    for game = 1, 100 do
        local okRun = pcall(function()
            local teamA, teamB = {}, {}
            local sizeA = rng:nextInt(1, 6)
            local sizeB = rng:nextInt(1, 6)
            for j = 1, sizeA do
                teamA[j] = BattleEngine.newPokemon(rng:nextInt(1, 151), rng:nextInt(1, 100))
            end
            for j = 1, sizeB do
                teamB[j] = BattleEngine.newPokemon(rng:nextInt(1, 151), rng:nextInt(1, 100))
            end
            local battle = BattleEngine.newBattle(teamA, teamB, {
                seed = rng:nextInt(1, 2 ^ 31), mode = "bot",
            })
            local turns = 0
            while not battle.over and turns < 250 do
                turns = turns + 1
                battle:runTurn({
                    [1] = Bot.chooseMove(battle, 1),
                    [2] = Bot.chooseMove(battle, 2),
                })
                for side = 1, 2 do
                    for _, p in ipairs(battle.sides[side].team) do
                        if p.hp < 0 then invariantErrors = invariantErrors + 1 end
                        if p.hp > p.maxHp then invariantErrors = invariantErrors + 1 end
                        for _, val in pairs(p.stages) do
                            if val < -6 or val > 6 then invariantErrors = invariantErrors + 1 end
                        end
                        if p.fainted and p.hp > 0 then invariantErrors = invariantErrors + 1 end
                        if p.hp <= 0 and not p.fainted then invariantErrors = invariantErrors + 1 end
                    end
                    if battle.sides[side].active < 1 or battle.sides[side].active > #battle.sides[side].team then
                        invariantErrors = invariantErrors + 1
                    end
                end
                for side = 1, 2 do
                    local active = battle:active(side)
                    if active then
                        for _, m in ipairs(active.moves) do
                            if m.pp < 0 then invariantErrors = invariantErrors + 1 end
                            if m.pp > m.maxPp then invariantErrors = invariantErrors + 1 end
                        end
                    end
                end
            end
            if battle.over then completedBattles = completedBattles + 1 end
        end)
        if not okRun then invariantErrors = invariantErrors + 1 end
    end

    eq(invariantErrors, 0, "Invariants: no violations in 100 random battles")
    eq(completedBattles, 100, "Invariants: all 100 random battles completed")
end

----------------------------------------------------------------------
-- 8. Every damaging move deals > 0 damage when not immune
----------------------------------------------------------------------
do
    local atk = BattleEngine.newPokemon(150, 100)
    local battle = BattleEngine.newBattle({ atk }, { BattleEngine.newPokemon(1, 100) }, { seed = 1 })
    local def = battle:active(2)

    for id, m in pairs(Moves.list) do
        if m.power > 0 or m.fixed then
            local cat = m.cat or Types.categoryFor(m.type)
            if cat ~= "status" then
                def.hp = def.maxHp
                def.fainted = false
                def.volatile = {}
                def.status = nil
                def.stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0, eva = 0 }
                atk.hp = atk.maxHp
                atk.fainted = false
                atk.volatile = {}
                atk.status = nil
                atk.stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0, eva = 0 }

                if m.fixed ~= "counter" then
                    local dmg = battle:calcDamage(atk, def, m)
                    local eff = Types.getEffectivenessVs(m.type, def.types[1], def.types[2])
                    if eff > 0 then
                        ok(dmg > 0, "Move " .. id .. " deals > 0 damage (got " .. dmg .. ")")
                    end
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- 9. Status moves apply their effects
----------------------------------------------------------------------
do
    local statusMoves = {}
    for id, m in pairs(Moves.list) do
        if m.effect and (m.effect.status or m.effect.toxic) then
            statusMoves[#statusMoves + 1] = { id = id, move = m }
        end
    end
    ok(#statusMoves > 0, "Found status-inflicting moves (" .. #statusMoves .. ")")

    for _, sm in ipairs(statusMoves) do
        local atk = BattleEngine.newPokemon(6, 100)
        local def = BattleEngine.newPokemon(9, 100)
        local b = BattleEngine.newBattle({ atk }, { def }, { seed = 1 })
        def.status = nil
        def.volatile = {}
        local result = {}
        local applyOk = pcall(function()
            b:applyStatusMove(atk, def, sm.move, result)
        end)
        ok(applyOk, "Status move " .. sm.id .. " applies without error")
        if sm.move.effect.toxic then
            eq(def.status, "poison", "Toxic move " .. sm.id .. " sets poison status")
            eq(def.volatile.toxic, true, "Toxic move " .. sm.id .. " sets toxic flag")
        end
    end

    local boostMoves = {}
    for id, m in pairs(Moves.list) do
        if m.effect and m.effect.boost and not m.effect.boostChance then
            boostMoves[#boostMoves + 1] = { id = id, move = m }
        end
    end
    for _, bm in ipairs(boostMoves) do
        local atk = BattleEngine.newPokemon(6, 100)
        local def = BattleEngine.newPokemon(9, 100)
        local b = BattleEngine.newBattle({ atk }, { def }, { seed = 1 })
        local result = {}
        local applyOk = pcall(function()
            b:applyStatusMove(atk, def, bm.move, result)
        end)
        ok(applyOk, "Boost move " .. bm.id .. " applies without error")
        local stat = bm.move.effect.boost.stat
        local stages = bm.move.effect.boost.stages
        local target = (stages < 0) and def or atk
        eq(target.stages[stat], stages, "Boost move " .. bm.id .. " sets " .. stat .. " to " .. stages)
    end

    local healMoves = {}
    for id, m in pairs(Moves.list) do
        if m.effect and m.effect.heal then
            healMoves[#healMoves + 1] = id
        end
    end
    for _, id in ipairs(healMoves) do
        local atk = BattleEngine.newPokemon(6, 100)
        atk.hp = math.floor(atk.maxHp / 2)
        local def = BattleEngine.newPokemon(9, 100)
        local b = BattleEngine.newBattle({ atk }, { def }, { seed = 1 })
        local m = Moves.get(id)
        local result = {}
        b:applyStatusMove(atk, def, m, result)
        ok(atk.hp > math.floor(atk.maxHp / 2), "Heal move " .. id .. " restores HP")
    end

    local restMove = Moves.get("Rest")
    if restMove then
        local atk = BattleEngine.newPokemon(6, 100)
        atk.hp = 10
        atk.status = "burn"
        local def = BattleEngine.newPokemon(9, 100)
        local b = BattleEngine.newBattle({ atk }, { def }, { seed = 1 })
        b:applyStatusMove(atk, def, restMove, {})
        eq(atk.hp, atk.maxHp, "Rest fully heals")
        eq(atk.status, "sleep", "Rest puts user to sleep")
    end

    local hazeMove = Moves.get("Haze")
    if hazeMove then
        local atk = BattleEngine.newPokemon(6, 100)
        local def = BattleEngine.newPokemon(9, 100)
        atk.stages.atk = 3
        def.stages.def = -2
        local b = BattleEngine.newBattle({ atk }, { def }, { seed = 1 })
        b:applyStatusMove(atk, def, hazeMove, {})
        eq(atk.stages.atk, 0, "Haze resets attacker stages")
        eq(def.stages.def, 0, "Haze resets defender stages")
    end

    local subMove = Moves.get("Substitute")
    if subMove then
        local atk = BattleEngine.newPokemon(6, 100)
        local def = BattleEngine.newPokemon(9, 100)
        local b = BattleEngine.newBattle({ atk }, { def }, { seed = 1 })
        local hpBefore = atk.hp
        b:applyStatusMove(atk, def, subMove, {})
        local cost = math.floor(atk.maxHp / 4)
        eq(atk.hp, hpBefore - cost, "Substitute costs 1/4 max HP")
        eq(atk.volatile.substitute, cost, "Substitute HP = 1/4 max HP")
    end

    local transformMove = Moves.get("Transform")
    if transformMove then
        local atk = BattleEngine.newPokemon(6, 100)
        local def = BattleEngine.newPokemon(9, 100)
        local b = BattleEngine.newBattle({ atk }, { def }, { seed = 1 })
        b:applyStatusMove(atk, def, transformMove, {})
        eq(atk.stats.atk, def.stats.atk, "Transform copies atk")
        eq(atk.stats.def, def.stats.def, "Transform copies def")
        eq(atk.stats.spa, def.stats.spa, "Transform copies spa")
        eq(atk.stats.spe, def.stats.spe, "Transform copies spe")
        eq(atk.types[1], def.types[1], "Transform copies type 1")
    end
end

----------------------------------------------------------------------
-- 10. Net message encode/decode round-trip
----------------------------------------------------------------------
do
    local messages = {
        Net.buildChallenge("A", "B", 6),
        Net.buildChallengeResponse("B", "A", true),
        Net.buildChallengeResponse("B", "A", false, "declined"),
        Net.buildChallengeResponse("A", "B", false, "cancelled"),
        Net.buildStart("A", "B", 12345, { { id = 1, level = 100, moves = { "Tackle" } } }),
        Net.buildChoice("A", "B", 1, { type = "move", index = 2 }),
        Net.buildChoice("A", "B", 3, { type = "switch", index = 1 }),
        Net.buildResign("A", "B"),
        Net.buildResult("A", "B", 1, 25),
        Net.buildHello("Alice"),
    }
    for i, msg in ipairs(messages) do
        local msgType, data, decodeOk = Net.decode(msg)
        ok(decodeOk, "Net round-trip message #" .. i .. " decodes")
        ok(msgType ~= nil, "Net round-trip message #" .. i .. " has type")
        ok(data ~= nil, "Net round-trip message #" .. i .. " has data")
    end

    local complexChoice = Net.buildChoice("A", "B", 5, { type = "move", index = 3, extra = { nested = true } })
    local ct, cd, cok = Net.decode(complexChoice)
    eq(cok, true, "Net: complex choice decodes")
    eq(cd.choice.type, "move", "Net: complex choice type preserved")
    eq(cd.choice.extra.nested, true, "Net: nested data preserved")

    local strDec = Json.decode(Json.encode("hello"))
    eq(strDec, "hello", "JSON string round-trip")
    local numDec = Json.decode(Json.encode(42))
    eq(numDec, 42, "JSON number round-trip")
    local boolDec = Json.decode(Json.encode(true))
    eq(boolDec, true, "JSON boolean round-trip")
end

----------------------------------------------------------------------
-- 11. Stats calculation sanity
----------------------------------------------------------------------
do
    local mewtwo = PokemonData.get(150)
    local stats100 = Stats.computeStats(mewtwo, 100)
    ok(stats100.hp > 300, "Mewtwo L100 HP > 300 (got " .. stats100.hp .. ")")
    ok(stats100.spa > 300, "Mewtwo L100 SpA > 300 (got " .. stats100.spa .. ")")

    local stats1 = Stats.computeStats(mewtwo, 1)
    ok(stats1.hp < stats100.hp, "Level 1 HP < Level 100 HP")
    ok(stats1.spa < stats100.spa, "Level 1 SpA < Level 100 SpA")

    local bulbasaur = PokemonData.get(1)
    -- Gen 1 max IV/EV formula: HP = floor((2*base+93)*L/100)+L+10, others = floor((2*base+93)*L/100)+5
    local expectedHp100 = math.floor((2 * 45 + 93) * 100 / 100) + 100 + 10
    eq(Stats.computeStats(bulbasaur, 100).hp, expectedHp100, "Bulbasaur L100 HP formula")
    eq(expectedHp100, 293, "Bulbasaur L100 HP canonical value (2*45+203)")

    local expectedAtk100 = math.floor((2 * 49 + 93) * 100 / 100) + 5
    eq(Stats.computeStats(bulbasaur, 100).atk, expectedAtk100, "Bulbasaur L100 Atk formula")
    eq(expectedAtk100, 196, "Bulbasaur L100 Atk canonical value (2*49+98)")

    -- Mewtwo L100 canonical values
    local mewtwoSpA = Stats.computeStats(mewtwo, 100).spa
    eq(mewtwoSpA, 406, "Mewtwo L100 SpA canonical value (2*154+98)")
    local mewtwoHp = Stats.computeStats(mewtwo, 100).hp
    eq(mewtwoHp, 415, "Mewtwo L100 HP canonical value (2*106+203)")

    local prevHp = 0
    for lv = 1, 100 do
        local s = Stats.computeStats(bulbasaur, lv)
        ok(s.hp > prevHp, "Bulbasaur HP increases at level " .. lv)
        prevHp = s.hp
    end
end

----------------------------------------------------------------------
-- 12. defaultMoves picks the 4 most recent learnset moves
----------------------------------------------------------------------
do
    local bulbasaur = PokemonData.get(1)
    local moves = BattleEngine.defaultMoves(bulbasaur, 100)
    eq(#moves, 4, "Bulbasaur L100 default moves = 4")
    eq(moves[1].id, "PoisonSting", "Default move 1 = PoisonSting (level 15)")
    eq(moves[2].id, "RazorLeaf", "Default move 2 = RazorLeaf (level 20)")
    eq(moves[3].id, "SleepPowder", "Default move 3 = SleepPowder (level 27)")
    eq(moves[4].id, "SolarBeam", "Default move 4 = SolarBeam (level 34)")

    local moves10 = BattleEngine.defaultMoves(bulbasaur, 10)
    eq(#moves10, 4, "Bulbasaur L10 default moves = 4")

    local moves1 = BattleEngine.defaultMoves(bulbasaur, 1)
    eq(#moves1, 1, "Bulbasaur L1 default moves = 1")
    eq(moves1[1].id, "Tackle", "Bulbasaur L1 only knows Tackle")

    local legal = BattleEngine.legalMoves(bulbasaur, 100)
    eq(#legal, 8, "Bulbasaur L100 has 8 legal moves")
    local legal1 = BattleEngine.legalMoves(bulbasaur, 1)
    eq(#legal1, 1, "Bulbasaur L1 has 1 legal move")
end

----------------------------------------------------------------------
-- 13. Struggle behavior
----------------------------------------------------------------------
do
    eq(BattleEngine.STRUGGLE.power, 50, "Struggle power = 50")
    eq(BattleEngine.STRUGGLE.acc, 100, "Struggle acc = 100")
    eq(BattleEngine.STRUGGLE.effect.recoil, 0.25, "Struggle recoil = 0.25")

    local strugAtk = BattleEngine.newPokemon(68, 100, { moves = { "Tackle" } })
    strugAtk.moves[1].pp = 0
    local strugDef = BattleEngine.newPokemon(1, 100)
    local strugBattle = BattleEngine.newBattle({ strugAtk }, { strugDef }, { seed = 1 })
    local hpAtkBefore = strugAtk.hp
    local hpDefBefore = strugDef.hp
    strugBattle:useMove(1, 1)
    ok(strugDef.hp < hpDefBefore, "Struggle deals damage to defender")
    ok(strugAtk.hp < hpAtkBefore, "Struggle deals recoil to attacker")
end

----------------------------------------------------------------------
-- 14. Multi-hit moves
----------------------------------------------------------------------
do
    local mhAtk = BattleEngine.newPokemon(15, 100, { moves = { "PinMissile" } })
    local mhDef = BattleEngine.newPokemon(1, 100)
    local mhBattle = BattleEngine.newBattle({ mhAtk }, { mhDef }, { seed = 1 })

    local totalHits = 0
    for _ = 1, 100 do
        mhDef.hp = mhDef.maxHp
        mhDef.fainted = false
        mhAtk.hp = mhAtk.maxHp
        mhAtk.fainted = false
        mhAtk.moves[1].pp = mhAtk.moves[1].maxPp
        local prevLogLen = #mhBattle.log
        mhBattle:useMove(1, 1)
        for i = prevLogLen + 1, #mhBattle.log do
            local hits = mhBattle.log[i]:match("It hit (%d+) times!")
            if hits then totalHits = totalHits + tonumber(hits) end
        end
        if mhDef.hp <= 0 then break end
    end
    ok(totalHits > 0, "Multi-hit moves produce hit count messages (total hits=" .. totalHits .. ")")

    local dkAtk = BattleEngine.newPokemon(106, 100, { moves = { "DoubleKick" } })
    local dkDef = BattleEngine.newPokemon(1, 100)
    local dkBattle = BattleEngine.newBattle({ dkAtk }, { dkDef }, { seed = 1 })
    dkBattle:useMove(1, 1)
    local found2 = false
    for _, msg in ipairs(dkBattle.log) do
        if msg:match("It hit 2 times!") then found2 = true end
    end
    ok(found2, "Double Kick hits exactly 2 times")

    local tnAtk = BattleEngine.newPokemon(15, 100, { moves = { "Twineedle" } })
    local tnDef = BattleEngine.newPokemon(1, 100)
    local tnBattle = BattleEngine.newBattle({ tnAtk }, { tnDef }, { seed = 1 })
    tnBattle:useMove(1, 1)
    local foundTn = false
    for _, msg in ipairs(tnBattle.log) do
        if msg:match("It hit 2 times!") then foundTn = true end
    end
    ok(foundTn, "Twineedle hits exactly 2 times")
end

----------------------------------------------------------------------
-- 15. Two-turn moves (SolarBeam, Fly, Dig)
----------------------------------------------------------------------
do
    local solarAtk = BattleEngine.newPokemon(3, 100, { moves = { "SolarBeam" } })
    local solarDef = BattleEngine.newPokemon(9, 100)
    local solarBattle = BattleEngine.newBattle({ solarAtk }, { solarDef }, { seed = 1 })

    local hpBefore = solarDef.hp
    solarBattle:useMove(1, 1)
    eq(solarDef.hp, hpBefore, "SolarBeam turn 1: no damage (charging)")
    eq(solarAtk.volatile.charging, "charge", "SolarBeam turn 1: charging flag set")

    solarBattle:useMove(1, 1)
    ok(solarDef.hp < hpBefore, "SolarBeam turn 2: deals damage")
    eq(solarAtk.volatile.charging, nil, "SolarBeam turn 2: charging flag cleared")

    local flyAtk = BattleEngine.newPokemon(149, 100, { moves = { "Fly" } })
    local flyDef = BattleEngine.newPokemon(9, 100)
    local flyBattle = BattleEngine.newBattle({ flyAtk }, { flyDef }, { seed = 1 })
    hpBefore = flyDef.hp
    flyBattle:useMove(1, 1)
    eq(flyDef.hp, hpBefore, "Fly turn 1: no damage (charging)")
    flyBattle:useMove(1, 1)
    ok(flyDef.hp < hpBefore, "Fly turn 2: deals damage")
end

----------------------------------------------------------------------
-- 16. Priority moves go first
----------------------------------------------------------------------
do
    -- Use low-level Pokemon so neither KOs the other in one hit
    local fastTackle = BattleEngine.newPokemon(25, 5, { moves = { "Tackle" } })
    local slowQuick = BattleEngine.newPokemon(143, 5, { moves = { "QuickAttack" } })
    local priBattle = BattleEngine.newBattle({ fastTackle }, { slowQuick }, { seed = 1 })

    eq(priBattle:speedOf(fastTackle) > priBattle:speedOf(slowQuick), true,
        "Pikachu is faster than Snorlax")

    priBattle:runTurn({
        [1] = { type = "move", index = 1 },
        [2] = { type = "move", index = 1 },
    })
    local quickIdx, tackleIdx = nil, nil
    for i, msg in ipairs(priBattle.log) do
        if msg:match("used Quick Attack") and not quickIdx then quickIdx = i end
        if msg:match("used Tackle") and not tackleIdx then tackleIdx = i end
    end
    ok(quickIdx ~= nil, "Quick Attack was used")
    ok(tackleIdx ~= nil, "Tackle was used")
    ok(quickIdx < tackleIdx, "Quick Attack (priority +1) goes before Tackle (priority 0) despite lower speed")

    local counterUser = BattleEngine.newPokemon(68, 5, { moves = { "Counter" } })
    local normalUser = BattleEngine.newPokemon(25, 5, { moves = { "Tackle" } })
    local cntBattle = BattleEngine.newBattle({ counterUser }, { normalUser }, { seed = 1 })
    cntBattle:runTurn({
        [1] = { type = "move", index = 1 },
        [2] = { type = "move", index = 1 },
    })
    local counterIdx, tackleIdx2 = nil, nil
    for i, msg in ipairs(cntBattle.log) do
        if msg:match("used Counter") and not counterIdx then counterIdx = i end
        if msg:match("used Tackle") and not tackleIdx2 then tackleIdx2 = i end
    end
    ok(tackleIdx2 ~= nil, "Counter battle: Tackle was used")
    ok(counterIdx ~= nil, "Counter battle: Counter was used")
    ok(tackleIdx2 < counterIdx, "Tackle (priority 0) goes before Counter (priority -1)")
end

----------------------------------------------------------------------
-- 17. OHKO moves
----------------------------------------------------------------------
do
    local ohkoAtk = BattleEngine.newPokemon(149, 100)
    local ohkoDef = BattleEngine.newPokemon(1, 100)
    local ohkoBattle = BattleEngine.newBattle({ ohkoAtk }, { ohkoDef }, { seed = 1 })

    local hornDrill = Moves.get("HornDrill2")
    local dmg = ohkoBattle:calcDamage(ohkoAtk, ohkoDef, hornDrill)
    eq(dmg, ohkoDef.hp, "Horn Drill at equal level deals full HP damage (OHKO)")

    local lowAtk = BattleEngine.newPokemon(149, 50)
    local highDef = BattleEngine.newPokemon(1, 100)
    local lowBattle = BattleEngine.newBattle({ lowAtk }, { highDef }, { seed = 1 })
    local dmg2 = lowBattle:calcDamage(lowAtk, highDef, hornDrill)
    eq(dmg2, 0, "Horn Drill at lower level deals 0 damage")
end

----------------------------------------------------------------------
-- 18. Fixed damage moves
----------------------------------------------------------------------
do
    local atk = BattleEngine.newPokemon(150, 100)
    local def = BattleEngine.newPokemon(1, 100)
    local b = BattleEngine.newBattle({ atk }, { def }, { seed = 1 })

    eq(b:calcDamage(atk, def, Moves.get("SeismicToss")), 100, "Seismic Toss = level damage")
    eq(b:calcDamage(atk, def, Moves.get("NightShade")), 100, "Night Shade = level damage")
    eq(b:calcDamage(atk, def, Moves.get("DragonRage")), 40, "Dragon Rage = 40 damage")
    eq(b:calcDamage(atk, def, Moves.get("SonicBoom2")), 20, "Sonic Boom = 20 damage")

    def.hp = 200
    eq(b:calcDamage(atk, def, Moves.get("SuperFang2")), 100, "Super Fang = half of current HP")

    local atk50 = BattleEngine.newPokemon(150, 50)
    local b50 = BattleEngine.newBattle({ atk50 }, { def }, { seed = 1 })
    eq(b50:calcDamage(atk50, def, Moves.get("SeismicToss")), 50, "Seismic Toss at L50 = 50 damage")
end

----------------------------------------------------------------------
-- 19. Immunity: no damage through immunity
----------------------------------------------------------------------
do
    local normalAtk = BattleEngine.newPokemon(1, 100, { moves = { "Tackle" } })
    local ghostDef = BattleEngine.newPokemon(94, 100)
    local immBattle = BattleEngine.newBattle({ normalAtk }, { ghostDef }, { seed = 1 })
    local result = immBattle:useMove(1, 1)
    eq(result.immune, true, "Normal move is immune vs Ghost")
    eq(ghostDef.hp, ghostDef.maxHp, "No damage through immunity")

    local elecAtk = BattleEngine.newPokemon(25, 100, { moves = { "Thunderbolt" } })
    local groundDef = BattleEngine.newPokemon(51, 100)
    local immBattle2 = BattleEngine.newBattle({ elecAtk }, { groundDef }, { seed = 1 })
    local result2 = immBattle2:useMove(1, 1)
    eq(result2.immune, true, "Electric move is immune vs Ground")

    local fightAtk = BattleEngine.newPokemon(68, 100, { moves = { "KarateChop" } })
    local ghostDef2 = BattleEngine.newPokemon(94, 100)
    local immBattle3 = BattleEngine.newBattle({ fightAtk }, { ghostDef2 }, { seed = 1 })
    local result3 = immBattle3:useMove(1, 1)
    eq(result3.immune, true, "Fighting move is immune vs Ghost")

    local groundAtk = BattleEngine.newPokemon(51, 100, { moves = { "Dig" } })
    local flyingDef = BattleEngine.newPokemon(149, 100)
    local immBattle4 = BattleEngine.newBattle({ groundAtk }, { flyingDef }, { seed = 1 })
    immBattle4:useMove(1, 1)
    local result4 = immBattle4:useMove(1, 1)
    eq(result4.immune, true, "Ground move is immune vs Flying")
end

----------------------------------------------------------------------
-- 20. Burn halves physical attack
----------------------------------------------------------------------
do
    local atk = BattleEngine.newPokemon(68, 100)
    local def = BattleEngine.newPokemon(9, 100)
    local b = BattleEngine.newBattle({ atk }, { def }, { seed = 1 })

    -- Gen 1: burn is ignored on critical hits, so we must average over many
    -- trials. Machop base speed 35 -> crit threshold = floor(35/2)*2 = 70,
    -- crit rate ~27%. With highCrit (Karate Chop), threshold = 70*8=255 capped,
    -- crit rate ~99.6% -- so use a non-highCrit move for the burn test.
    local tackle = Moves.get("Tackle")

    -- Burn does NOT affect special damage (average over many trials)
    atk.status = nil
    local specialMove = Moves.get("Flamethrower")
    local specNormalSum, specBurnedSum = 0, 0
    for _ = 1, 300 do
        specNormalSum = specNormalSum + b:calcDamage(atk, def, specialMove)
        atk.status = "burn"
        specBurnedSum = specBurnedSum + b:calcDamage(atk, def, specialMove)
        atk.status = nil
    end
    local specRatio = (specBurnedSum / 300) / (specNormalSum / 300)
    ok(specRatio > 0.85, "Burn does not halve special damage (avg ratio=" .. string.format("%.2f", specRatio) .. ")")

    -- Verify burn DOES halve physical on non-crit hits.
    -- We control for crits by checking per-trial: only compare non-crit results.
    -- Simpler: use a very slow Pokemon so crit rate is near 0.
    local slowAtk = BattleEngine.newPokemon(74, 100) -- Geodude, base spe 20
    local slowDef = BattleEngine.newPokemon(9, 100)
    local slowB = BattleEngine.newBattle({ slowAtk }, { slowDef }, { seed = 7 })
    local dmgNormal = slowB:calcDamage(slowAtk, slowDef, tackle)
    slowAtk.status = "burn"
    local dmgBurned = slowB:calcDamage(slowAtk, slowDef, tackle)
    -- Geodude base spe 20: threshold = floor(20/2)*2 = 20, crit rate = 20/256 ~ 7.8%
    -- With one call each, there's a small chance of a crit on the normal roll.
    -- Average over 300 trials for reliability.
    local physNormalSum, physBurnedSum = 0, 0
    for _ = 1, 300 do
        physNormalSum = physNormalSum + slowB:calcDamage(slowAtk, slowDef, tackle)
        slowAtk.status = "burn"
        physBurnedSum = physBurnedSum + slowB:calcDamage(slowAtk, slowDef, tackle)
        slowAtk.status = nil
    end
    local physRatio = (physBurnedSum / 300) / (physNormalSum / 300)
    ok(physRatio < 0.65 and physRatio > 0.4, "Burn roughly halves physical damage (avg ratio=" .. string.format("%.2f", physRatio) .. ")")

    -- Gen 1: crit ignores burn halving (crit uses unmodified attack)
    local fastAtk = BattleEngine.newPokemon(150, 100) -- Mewtwo, base spe 130
    local fastDef = BattleEngine.newPokemon(9, 100)
    local fastB = BattleEngine.newBattle({ fastAtk }, { fastDef }, { seed = 3 })
    local critIgnoresBurnSum = 0
    local critCount = 0
    for _ = 1, 300 do
        fastB._lastCrit = nil
        fastAtk.status = "burn"
        fastB:calcDamage(fastAtk, fastDef, tackle)
        if fastB._lastCrit then
            critCount = critCount + 1
        end
    end
    -- Mewtwo base spe 130: threshold = floor(130/2)*2 = 130, crit rate ~50.8%
    ok(critCount > 100 and critCount < 200, "Mewtwo crit rate ~50% with Tackle (got " .. critCount .. "/300)")
end

----------------------------------------------------------------------
-- 21. Gen 1 mechanics: crit uses base speed, high-crit x8, FE quarters
----------------------------------------------------------------------
do
    -- High-crit move: Slash (Normal, highCrit). Mewtwo base spe 130.
    -- threshold = floor(130/2)*8 = 65*8 = 520 -> capped 255 -> crit rate ~99.6%
    local mewtwo = BattleEngine.newPokemon(150, 100)
    local blastoise = BattleEngine.newPokemon(9, 100)
    local b = BattleEngine.newBattle({ mewtwo }, { blastoise }, { seed = 42 })
    local slash = Moves.get("Slash")
    local critCount = 0
    for _ = 1, 200 do
        b._lastCrit = nil
        b:calcDamage(mewtwo, blastoise, slash)
        if b._lastCrit then critCount = critCount + 1 end
    end
    ok(critCount > 190, "High-crit Slash crits ~99.6% for Mewtwo (got " .. critCount .. "/200)")

    -- Normal move: Tackle. Mewtwo base spe 130.
    -- threshold = floor(130/2)*2 = 130 -> crit rate = 130/256 ~ 50.8%
    local tackle = Moves.get("Tackle")
    critCount = 0
    for _ = 1, 200 do
        b._lastCrit = nil
        b:calcDamage(mewtwo, blastoise, tackle)
        if b._lastCrit then critCount = critCount + 1 end
    end
    ok(critCount > 70 and critCount < 130, "Normal Tackle crits ~50% for Mewtwo (got " .. critCount .. "/200)")

    -- Low base speed: Geodude base spe 20 -> threshold = floor(20/2)*2 = 20 -> ~7.8%
    local geodude = BattleEngine.newPokemon(74, 100)
    critCount = 0
    for _ = 1, 200 do
        b._lastCrit = nil
        b:calcDamage(geodude, blastoise, tackle)
        if b._lastCrit then critCount = critCount + 1 end
    end
    ok(critCount > 0 and critCount < 40, "Geodude crits ~7.8% with Tackle (got " .. critCount .. "/200)")

    -- Focus Energy bug: quarters crit rate instead of boosting
    local feAtk = BattleEngine.newPokemon(150, 100)
    local feDef = BattleEngine.newPokemon(9, 100)
    local feB = BattleEngine.newBattle({ feAtk }, { feDef }, { seed = 99 })
    -- Without FE: threshold = 130, crit rate ~50.8%
    local critNoFE = 0
    for _ = 1, 200 do
        feB._lastCrit = nil
        feB:calcDamage(feAtk, feDef, tackle)
        if feB._lastCrit then critNoFE = critNoFE + 1 end
    end
    -- With FE: threshold = floor(130/2) = 65, crit rate ~25.4% (quartered)
    feAtk.volatile.focusEnergy = true
    local critFE = 0
    for _ = 1, 200 do
        feB._lastCrit = nil
        feB:calcDamage(feAtk, feDef, tackle)
        if feB._lastCrit then critFE = critFE + 1 end
    end
    ok(critFE < critNoFE, "Focus Energy quarters crit rate in Gen 1 (" .. critFE .. " < " .. critNoFE .. ")")
    ok(critFE > 20 and critFE < 80, "FE crit rate ~25% for Mewtwo (got " .. critFE .. "/200)")

    -- Crit ignores stat stages: boost attacker's atk by +6, crit should use unmodified atk
    local stageAtk = BattleEngine.newPokemon(68, 100) -- Machop
    local stageDef = BattleEngine.newPokemon(9, 100)
    local stageB = BattleEngine.newBattle({ stageAtk }, { stageDef }, { seed = 5 })
    stageAtk.stages.atk = 6 -- +6 = 4x attack
    -- Force a crit by using a very fast attacker
    local fastAtk2 = BattleEngine.newPokemon(150, 100)
    fastAtk2.stages.atk = 6
    local stageB2 = BattleEngine.newBattle({ fastAtk2 }, { stageDef }, { seed = 5 })
    -- On crit, attack should be unmodified (no 4x boost)
    -- We verify by comparing crit damage to non-crit-no-stage damage
    local critDmgs = {}
    local normalDmgs = {}
    for _ = 1, 300 do
        stageB2._lastCrit = nil
        local d = stageB2:calcDamage(fastAtk2, stageDef, tackle)
        if stageB2._lastCrit then
            critDmgs[#critDmgs + 1] = d
        end
    end
    -- Without stages, crit damage should be similar range
    fastAtk2.stages.atk = 0
    local noStageCritDmgs = {}
    for _ = 1, 300 do
        stageB2._lastCrit = nil
        local d = stageB2:calcDamage(fastAtk2, stageDef, tackle)
        if stageB2._lastCrit then
            noStageCritDmgs[#noStageCritDmgs + 1] = d
        end
    end
    if #critDmgs > 0 and #noStageCritDmgs > 0 then
        local avgCrit = 0
        for _, d in ipairs(critDmgs) do avgCrit = avgCrit + d end
        avgCrit = avgCrit / #critDmgs
        local avgNoStage = 0
        for _, d in ipairs(noStageCritDmgs) do avgNoStage = avgNoStage + d end
        avgNoStage = avgNoStage / #noStageCritDmgs
        -- Crit with +6 stages should be ~same as crit without stages (both use unmodified atk)
        local ratio = avgCrit / avgNoStage
        ok(ratio > 0.9 and ratio < 1.1, "Crit ignores stat stages (ratio=" .. string.format("%.2f", ratio) .. ")")
    else
        ok(false, "Crit ignores stat stages (not enough crit samples)")
    end
end

----------------------------------------------------------------------
-- 22. Gen 1 mechanics: freeze never self-thaws
----------------------------------------------------------------------
do
    local atk = BattleEngine.newPokemon(68, 100, { moves = { "Tackle" } })
    local def = BattleEngine.newPokemon(9, 100, { moves = { "Tackle" } })
    atk.status = "freeze"
    local b = BattleEngine.newBattle({ atk }, { def }, { seed = 1 })
    local thawed = false
    for _ = 1, 50 do
        b:useMove(1, 1)
        if atk.status ~= "freeze" then thawed = true break end
    end
    ok(not thawed, "Frozen Pokemon never thaws on its own in Gen 1")
end

----------------------------------------------------------------------
-- 23. Gen 1 mechanics: sleep 1-7 turns, wake consumes turn
----------------------------------------------------------------------
do
    local atk = BattleEngine.newPokemon(68, 100, { moves = { "Tackle" } })
    local def = BattleEngine.newPokemon(9, 100, { moves = { "Tackle" } })
    atk.status = "sleep"
    atk.volatile.sleepTurns = 0
    atk.volatile.sleepMax = 1 -- will wake after 1 turn of sleep
    local b = BattleEngine.newBattle({ atk }, { def }, { seed = 1 })
    -- Turn 1: sleepTurns becomes 1, 1 <= 1 so still asleep
    b:useMove(1, 1)
    ok(atk.status == "sleep", "Pokemon still asleep on turn 1")
    ok(def.hp == def.maxHp, "No damage dealt while asleep")
    -- Turn 2: sleepTurns becomes 2, 2 > 1 so wakes up but CANNOT move
    local hpBefore = def.hp
    b:useMove(1, 1)
    ok(atk.status == nil, "Pokemon woke up on turn 2")
    ok(def.hp == hpBefore, "Waking up consumes the turn (no move executed)")
    -- Turn 3: should be able to move normally
    b:useMove(1, 1)
    ok(def.hp < hpBefore, "Pokemon can move after waking up")

    -- Sleep max is 1-7 (test that sleepMax can be set to 7)
    local atk2 = BattleEngine.newPokemon(68, 100, { moves = { "Tackle" } })
    local def2 = BattleEngine.newPokemon(9, 100, { moves = { "Tackle" } })
    atk2.status = "sleep"
    atk2.volatile.sleepTurns = 0
    atk2.volatile.sleepMax = 7
    local b2 = BattleEngine.newBattle({ atk2 }, { def2 }, { seed = 2 })
    local asleepTurns = 0
    for _ = 1, 8 do
        b2:useMove(1, 1)
        if atk2.status == "sleep" then
            asleepTurns = asleepTurns + 1
        end
    end
    ok(asleepTurns == 7, "Pokemon sleeps for 7 turns with sleepMax=7 (got " .. asleepTurns .. ")")
end

----------------------------------------------------------------------
-- 24. Gen 1 mechanics: confusion 2-5 turns, typeless self-hit
----------------------------------------------------------------------
do
    -- Confusion self-hit is typeless (neutral vs Ghost)
    local gengar = BattleEngine.newPokemon(94, 100) -- Ghost/Poison
    local b = BattleEngine.newBattle({ gengar }, { gengar }, { seed = 1 })
    local selfHitMove = { type = "???", cat = "physical", power = 40 }
    local dmg = b:calcDamage(gengar, gengar, selfHitMove)
    ok(dmg > 0, "Confusion self-hit deals damage to Ghost (typeless)")

    -- Normal-type 40-power self-hit would be 0 vs Ghost (immune)
    local normalSelfHit = { type = "Normal", cat = "physical", power = 40 }
    local effVsGhost = Types.getEffectivenessVs("Normal", "Ghost", "Poison")
    eq(effVsGhost, 0, "Normal is immune vs Ghost (confusion must be typeless)")

    -- Struggle is also typeless
    eq(Types.getEffectivenessVs("???", "Ghost", nil), 1, "Struggle/confusion type is neutral vs Ghost")
    eq(Types.getEffectivenessVs("???", "Normal", nil), 1, "Typeless is neutral vs Normal")
end

----------------------------------------------------------------------
-- 25. Gen 1 mechanics: status persists through switch
----------------------------------------------------------------------
do
    local team = {
        BattleEngine.newPokemon(68, 100, { moves = { "Tackle" } }),
        BattleEngine.newPokemon(9, 100, { moves = { "Tackle" } }),
    }
    team[1].status = "burn"
    local def = BattleEngine.newPokemon(1, 100, { moves = { "Tackle" } })
    local b = BattleEngine.newBattle(team, { def }, { seed = 1 })
    b:forceSwitch(1, 2)
    -- Switching should NOT clear major status from the switched-out Pokemon
    ok(team[1].status == "burn", "Burn persists on switched-out Pokemon")
    -- But the newly-switched-in Pokemon should have no status
    ok(team[2].status == nil, "Newly switched-in Pokemon has no status")
    -- Volatile and stages should reset
    team[1].stages.atk = 3
    team[1].volatile.confusionTurns = 2
    b:forceSwitch(1, 2) -- switch to 2 (already active? no, active is 2)
    -- Switch back to 1
    b:forceSwitch(1, 1)
    eq(team[1].stages.atk, 0, "Stat stages reset on switch")
    ok(team[1].volatile.confusionTurns == nil, "Volatile resets on switch")
    ok(team[1].status == "burn", "Burn still persists after switching back in")
end

----------------------------------------------------------------------
-- 26. Gen 1 mechanics: type-based status immunities
----------------------------------------------------------------------
do
    local fireMon = BattleEngine.newPokemon(58, 100, { moves = { "Tackle" } }) -- Growlithe (Fire)
    local atk = BattleEngine.newPokemon(68, 100, { moves = { "Ember" } })
    local b = BattleEngine.newBattle({ atk }, { fireMon }, { seed = 1 })
    local ember = Moves.get("Ember")
    -- Ember has 30% burn chance; force it by using applyStatusMove directly
    local fireDef = BattleEngine.newPokemon(58, 100)
    local result = {}
    b:applyStatusMove(atk, fireDef, { effect = { status = "burn" } }, result)
    ok(fireDef.status == nil, "Fire-type cannot be burned")

    -- Electric-type cannot be paralyzed
    local elecDef = BattleEngine.newPokemon(25, 100) -- Pikachu (Electric)
    b:applyStatusMove(atk, elecDef, { effect = { status = "paralysis" } }, result)
    ok(elecDef.status == nil, "Electric-type cannot be paralyzed")

    -- Ice-type cannot be frozen
    local iceDef = BattleEngine.newPokemon(87, 100) -- Dewgong (Water/Ice)
    b:applyStatusMove(atk, iceDef, { effect = { status = "freeze" } }, result)
    ok(iceDef.status == nil, "Ice-type cannot be frozen")

    -- Poison-type cannot be poisoned
    local poisonDef = BattleEngine.newPokemon(88, 100) -- Grimer (Poison)
    b:applyStatusMove(atk, poisonDef, { effect = { status = "poison" } }, result)
    ok(poisonDef.status == nil, "Poison-type cannot be poisoned")

    -- Poison-type cannot be badly poisoned (Toxic)
    local poisonDef2 = BattleEngine.newPokemon(88, 100)
    b:applyStatusMove(atk, poisonDef2, { effect = { toxic = true } }, result)
    ok(poisonDef2.status == nil, "Poison-type cannot be badly poisoned")
end

----------------------------------------------------------------------
-- 27. Gen 1 mechanics: Mist blocks stat drops
----------------------------------------------------------------------
do
    local atk = BattleEngine.newPokemon(68, 100, { moves = { "Tackle" } })
    local def = BattleEngine.newPokemon(1, 100, { moves = { "Growl" } })
    def.volatile.mist = true
    local b = BattleEngine.newBattle({ atk }, { def }, { seed = 1 })
    local result = {}
    b:applyStatusMove(atk, def, { effect = { boost = { stat = "atk", stages = -1 } } }, result)
    eq(def.stages.atk, 0, "Mist blocks opponent's stat drop")

    -- Mist does NOT block self boosts
    local atk2 = BattleEngine.newPokemon(68, 100)
    atk2.volatile.mist = true
    b:applyStatusMove(atk2, def, { effect = { boost = { stat = "atk", stages = 1 } } }, result)
    eq(atk2.stages.atk, 1, "Mist does not block self stat boosts")
end

----------------------------------------------------------------------
-- 28. Gen 1 mechanics: Substitute blocks secondary effects
----------------------------------------------------------------------
do
    local atk = BattleEngine.newPokemon(68, 100, { moves = { "BodySlam" } })
    local def = BattleEngine.newPokemon(1, 100, { moves = { "Tackle" } })
    def.volatile.substitute = 50
    local b = BattleEngine.newBattle({ atk }, { def }, { seed = 1 })
    -- BodySlam has 30% paralysis chance
    -- When substitute absorbs the hit, lastDamageTaken is set to 0
    -- and applyEffect should skip status/boost/flinch
    -- We use a large substitute HP so it never breaks during the test
    local paraApplied = false
    for trial = 1, 30 do
        def.hp = def.maxHp
        def.volatile.substitute = 9999 -- large enough to never break
        def.status = nil
        local r = b:useMove(1, 1)
        if def.status == "paralysis" then
            paraApplied = true
            break
        end
    end
    ok(not paraApplied, "Substitute blocks secondary status effects")

    -- Also verify: without substitute, paralysis CAN be applied (control test)
    -- Use a weaker attacker and high-HP defender to avoid fainting
    local weakAtk = BattleEngine.newPokemon(129, 100, { moves = { "BodySlam" } }) -- Magikarp
    local tankDef = BattleEngine.newPokemon(113, 100, { moves = { "Tackle" } }) -- Chansey, huge HP
    local ctrlB = BattleEngine.newBattle({ weakAtk }, { tankDef }, { seed = 5 })
    local paraAppliedNoSub = false
    for trial = 1, 300 do
        tankDef.hp = tankDef.maxHp
        tankDef.volatile.substitute = nil
        tankDef.status = nil
        tankDef.lastDamageTaken = 0
        local r = ctrlB:useMove(1, 1)
        if tankDef.status == "paralysis" then
            paraAppliedNoSub = true
            break
        end
    end
    ok(paraAppliedNoSub, "Without substitute, BodySlam can paralyze (control test)")
end

----------------------------------------------------------------------
-- 29. Gen 1 mechanics: Counter uses lastHitType
----------------------------------------------------------------------
do
    local atk = BattleEngine.newPokemon(68, 100, { moves = { "Tackle" } })
    local def = BattleEngine.newPokemon(9, 100, { moves = { "Counter" } })
    local b = BattleEngine.newBattle({ atk }, { def }, { seed = 1 })
    -- Hit the Counter user with a physical move
    b:useMove(1, 1) -- atk uses Tackle on def
    ok(def.lastDamageTaken > 0, "Counter user took physical damage")
    ok(def.lastHitType == "physical", "lastHitType is tracked as physical")
    -- Now Counter should deal 2x the last damage taken
    local counterDmg = b:calcDamage(def, atk, Moves.get("Counter"))
    ok(counterDmg > 0, "Counter deals damage based on last physical hit taken")
    eq(counterDmg, def.lastDamageTaken * 2, "Counter = 2x last physical damage taken")

    -- Counter should fail if last hit was special
    local atk2 = BattleEngine.newPokemon(94, 100, { moves = { "ConfuseRay" } }) -- Gengar, special move
    local def2 = BattleEngine.newPokemon(9, 100, { moves = { "Counter" } })
    local b2 = BattleEngine.newBattle({ atk2 }, { def2 }, { seed = 2 })
    -- Use a special move to hit def2
    def2.lastDamageTaken = 50
    def2.lastHitType = "special"
    local counterDmg2 = b2:calcDamage(def2, atk2, Moves.get("Counter"))
    eq(counterDmg2, 0, "Counter fails against special move")

    -- Counter should also work via useMove (full integration)
    local atk3 = BattleEngine.newPokemon(68, 100, { moves = { "Tackle" } })
    local def3 = BattleEngine.newPokemon(9, 100, { moves = { "Counter" } })
    local b3 = BattleEngine.newBattle({ atk3 }, { def3 }, { seed = 10 })
    b3:useMove(1, 1) -- Tackle hits def3
    local tackleDmg = def3.lastDamageTaken
    ok(tackleDmg > 0, "Tackle dealt damage for Counter integration test")
    local r3 = b3:useMove(2, 1) -- def3 uses Counter
    ok(r3.damage > 0, "Counter deals damage via useMove (got " .. r3.damage .. ")")
    eq(r3.damage, tackleDmg * 2, "Counter via useMove = 2x last damage (" .. r3.damage .. " = 2*" .. tackleDmg .. ")")
end

----------------------------------------------------------------------
-- 30. Gen 1 mechanics: Hyper Beam recharge + Explosion faints user
----------------------------------------------------------------------
do
    -- Hyper Beam recharge
    local atk = BattleEngine.newPokemon(68, 100, { moves = { "HyperBeam" } })
    local def = BattleEngine.newPokemon(9, 100, { moves = { "Tackle" } })
    local b = BattleEngine.newBattle({ atk }, { def }, { seed = 1 })
    b:useMove(1, 1)
    ok(def.hp < def.maxHp, "Hyper Beam deals damage")
    ok(atk.volatile.recharge == true, "Hyper Beam sets recharge flag")
    local hpBefore = def.hp
    b:useMove(1, 1)
    eq(def.hp, hpBefore, "Hyper Beam user must recharge (no damage on recharge turn)")
    ok(atk.volatile.recharge == nil, "Recharge flag cleared after recharge turn")

    -- Explosion faints user
    local atk2 = BattleEngine.newPokemon(68, 100, { moves = { "Explosion" } })
    local def2 = BattleEngine.newPokemon(9, 100, { moves = { "Tackle" } })
    local b2 = BattleEngine.newBattle({ atk2 }, { def2 }, { seed = 2 })
    local r = b2:useMove(1, 1)
    ok(def2.hp < def2.maxHp, "Explosion deals damage to target")
    eq(atk2.hp, 0, "Explosion faints the user")
    ok(r.selfKo == true, "Explosion result has selfKo flag")

    -- Self-Destruct also faints user
    local atk3 = BattleEngine.newPokemon(68, 100, { moves = { "SelfDestruct" } })
    local def3 = BattleEngine.newPokemon(9, 100, { moves = { "Tackle" } })
    local b3 = BattleEngine.newBattle({ atk3 }, { def3 }, { seed = 3 })
    b3:useMove(1, 1)
    eq(atk3.hp, 0, "Self-Destruct faints the user")
end

----------------------------------------------------------------------
-- 31. Gen 1 mechanics: stat >255 division rule
----------------------------------------------------------------------
do
    -- Mewtwo L100 atk = 2*110+98 = 318 > 255
    local mewtwo = BattleEngine.newPokemon(150, 100)
    ok(mewtwo.stats.atk > 255, "Mewtwo L100 atk > 255 (" .. mewtwo.stats.atk .. ")")
    local def = BattleEngine.newPokemon(9, 100) -- Blastoise, def = 2*79+98 = 256 > 255
    ok(def.stats.def > 255, "Blastoise L100 def > 255 (" .. def.stats.def .. ")")
    local b = BattleEngine.newBattle({ mewtwo }, { def }, { seed = 1 })
    local tackle = Moves.get("Tackle")
    -- Average over many trials to get a stable damage estimate
    local sum = 0
    local trials = 200
    for _ = 1, trials do
        sum = sum + b:calcDamage(mewtwo, def, tackle)
    end
    local avgDmg = sum / trials
    ok(avgDmg > 0, "Damage calculated with >255 stats (A and D both /4)")
    -- Verify: a=318, d=256 -> both >255 -> a=79, d=64
    -- base = floor(floor(floor(2*100/5+2)*40*79/64)/50)+2 = floor(floor(42*40*79/64)/50)+2
    -- = floor(floor(132720/64)/50)+2 = floor(2073/50)+2 = 41+2 = 43
    -- STAB=1 (Mewtwo is Psychic, Tackle is Normal), eff=1, rand avg ~236
    -- avg dmg ~ floor(43 * 236/255) = ~39.8
    -- But crits (Mewtwo base spe 130 -> ~50% crit) double level in formula:
    -- crit base = floor(floor(floor(2*100*2/5+2)*40*79/64)/50)+2
    --   = floor(floor(floor(82*40*79/64)/50)+2 = floor(floor(259120/64)/50)+2
    --   = floor(4048/50)+2 = 80+2 = 82 -> avg ~ floor(82*236/255) = ~75.8
    -- Mixed avg ~ (39.8 + 75.8) / 2 ~ 57.8
    ok(avgDmg >= 40 and avgDmg <= 75, "Damage with >255 stats in expected range (avg=" .. string.format("%.1f", avgDmg) .. ")")
end

----------------------------------------------------------------------
-- 32. Gen 1 mechanics: Skull Bash is two-turn
----------------------------------------------------------------------
do
    local atk = BattleEngine.newPokemon(68, 100, { moves = { "SkullBash2" } })
    local def = BattleEngine.newPokemon(9, 100, { moves = { "Tackle" } })
    local b = BattleEngine.newBattle({ atk }, { def }, { seed = 1 })
    b:useMove(1, 1)
    eq(def.hp, def.maxHp, "Skull Bash turn 1: charging (no damage)")
    ok(atk.volatile.charging == "charge", "Skull Bash sets charging state")
    b:useMove(1, 1)
    ok(def.hp < def.maxHp, "Skull Bash turn 2: deals damage")
end

----------------------------------------------------------------------
-- 33. Gen 1 mechanics: Razor Wind is high-crit + two-turn
----------------------------------------------------------------------
do
    local rw = Moves.get("RazorWind")
    ok(rw.highCrit == true, "Razor Wind has highCrit flag")
    ok(rw.twoTurn == "charge", "Razor Wind is two-turn")

    -- Verify all Gen 1 high-crit moves have the flag
    local highCritMoves = { "Slash", "KarateChop", "RazorLeaf", "Crabhammer2", "RazorWind" }
    for _, id in ipairs(highCritMoves) do
        local m = Moves.get(id)
        ok(m and m.highCrit == true, id .. " has highCrit flag")
    end

    -- Karate Chop is Normal-type in Gen 1
    local kc = Moves.get("KarateChop")
    eq(kc.type, "Normal", "Karate Chop is Normal-type in Gen 1")
end

----------------------------------------------------------------------
-- Summary
----------------------------------------------------------------------
print("")
print(string.format("Integration Tests: %d passed, %d failed", passed, failed))
_TEST_RESULT = { passed = passed, failed = failed, failures = failures }
if failed > 0 then
    print("Failures:")
    for _, f in ipairs(failures) do print("  - " .. f) end
end
if not _LUPA and os and os.exit then
    os.exit(failed > 0 and 1 or 0)
end
