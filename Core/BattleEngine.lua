local BattleEngine = {}
BattleEngine.__index = BattleEngine

local Types = require("Core.Data.Types")
local Moves = require("Core.Data.Moves")
local PokemonData = require("Core.Data.Pokemon")
local Stats = require("Core.Stats")
local PRNG = require("Core.Util.PRNG")

BattleEngine.MAX_TEAM = 6
BattleEngine.MAX_TURNS = 200 -- hard cap; prevents PP-stall infinite loops
BattleEngine.STRUGGLE = { id = "Struggle", type = "Normal", power = 50, acc = 100, pp = 1, effect = { recoil = 0.25 } }
BattleEngine.STATUSES = { burn = true, poison = true, paralysis = true, sleep = true, freeze = true, confusion = true }

local function clampStage(s) return math.max(-6, math.min(6, s)) end

-- Create a Pokemon instance ready for battle.
-- speciesId: number; level: number (default 100); opts: { moves, nickname }
-- opts.moves: list of move ids (up to 4). If omitted, the 4 most recent
-- learnset moves at that level are used.
function BattleEngine.newPokemon(speciesId, level, opts)
    opts = opts or {}
    local species = PokemonData.get(speciesId)
    if not species then error("BattleEngine.newPokemon: unknown species " .. tostring(speciesId), 2) end
    level = math.max(1, math.min(Stats.MAX_LEVEL, math.floor(level or 100)))
    local stats = Stats.computeStats(species, level)
    local moves = {}
    if opts.moves then
        for _, moveId in ipairs(opts.moves) do
            local def = Moves.get(moveId)
            if def then
                moves[#moves + 1] = { id = moveId, pp = def.pp, maxPp = def.pp }
            end
        end
    else
        moves = BattleEngine.defaultMoves(species, level)
    end
    if #moves == 0 then
        moves[1] = { id = "Tackle", pp = 35, maxPp = 35 }
    end
    return {
        id = speciesId,
        species = species,
        name = opts.nickname or species.name,
        nickname = opts.nickname or species.name,
        level = level,
        stats = stats,
        maxHp = stats.hp,
        hp = stats.hp,
        moves = moves,
        types = species.types,
        status = nil,
        stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0, eva = 0 },
        volatile = {},
        fainted = false,
        lastDamageTaken = 0,
        lastMoveType = nil,
    }
end

-- The 4 most recent moves this species can know at the given level.
function BattleEngine.defaultMoves(species, level)
    local known = {}
    for _, entry in ipairs(species.learnset) do
        local lv, moveId = entry[1], entry[2]
        if lv <= level and Moves.exists(moveId) then
            known[#known + 1] = moveId
        end
    end
    local picked = {}
    for i = #known, math.max(1, #known - 3), -1 do
        picked[#picked + 1] = known[i]
    end
    local out = {}
    for i = #picked, 1, -1 do
        local def = Moves.get(picked[i])
        out[#out + 1] = { id = picked[i], pp = def.pp, maxPp = def.pp }
    end
    return out
end

-- All move ids this species can legally know at the given level.
function BattleEngine.legalMoves(species, level)
    local out = {}
    for _, entry in ipairs(species.learnset) do
        local lv, moveId = entry[1], entry[2]
        if lv <= level and Moves.exists(moveId) then
            out[#out + 1] = moveId
        end
    end
    return out
end

function BattleEngine.hasMove(p, moveId)
    for _, m in ipairs(p.moves) do
        if m.id == moveId then return true end
    end
    return false
end

-- Create a battle between two teams. mode: "bot" or "pvp".
-- opts.seed: PRNG seed (required for pvp; generated for bot)
-- opts.onLog(msg): log callback
function BattleEngine.newBattle(teamA, teamB, opts)
    opts = opts or {}
    local b = {
        mode = opts.mode or "bot",
        rng = PRNG.new(opts.seed or PRNG.randomSeed()),
        seed = opts.seed,
        sides = {
            { team = teamA, active = 1, name = opts.nameA or "Player 1" },
            { team = teamB, active = 1, name = opts.nameB or "Player 2" },
        },
        turn = 0,
        over = false,
        winner = nil, -- 1 or 2 (nil = draw)
        log = {},
        onLog = opts.onLog,
        awaitingSwitch = {},
        firstFaint = nil, -- side that lost its first Pokemon (for "lead" tracking)
    }
    return setmetatable(b, BattleEngine)
end

function BattleEngine:logMsg(msg)
    self.log[#self.log + 1] = msg
    if self.onLog then self.onLog(msg) end
end

function BattleEngine:active(side)
    local s = self.sides[side]
    return s.team[s.active]
end

function BattleEngine:opponentOf(side)
    return side == 1 and 2 or 1
end

-- Check win/loss; returns true if the battle ended.
local function checkFaints(b)
    local sawFaint = false
    for side = 1, 2 do
        local p = b:active(side)
        if p and p.hp <= 0 and not p.fainted then
            p.fainted = true
            p.hp = 0
            b:logMsg(p.name .. " fainted!")
            if not b.firstFaint then b.firstFaint = side end
            sawFaint = true
        end
    end
    if sawFaint then
        for side = 1, 2 do
            local alive = false
            for _, p in ipairs(b.sides[side].team) do
                if not p.fainted then alive = true break end
            end
            if not alive then
                b.over = true
                b.winner = b:opponentOf(side)
                b:logMsg(b.sides[b.winner].name .. " won the battle!")
                return true
            end
            local activeP = b:active(side)
            if activeP and activeP.fainted then
                b.awaitingSwitch[side] = true
            end
        end
    end
    return b.over
end

function BattleEngine:forceSwitch(side, newIndex)
    local s = self.sides[side]
    if newIndex >= 1 and newIndex <= #s.team and not s.team[newIndex].fainted
        and newIndex ~= s.active then
        s.active = newIndex
        local p = s.team[newIndex]
        self:resetVolatile(p)
        self:logMsg(s.name .. " sent out " .. p.name .. "!")
        self.awaitingSwitch[side] = nil
        return true
    end
    return false
end

-- Auto-switch to the first non-fainted Pokemon (used when a side must switch).
function BattleEngine:autoSwitch(side)
    local s = self.sides[side]
    for i, p in ipairs(s.team) do
        if not p.fainted then
            return self:forceSwitch(side, i)
        end
    end
    return false
end

function BattleEngine:resetVolatile(p)
    p.stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0, eva = 0 }
    p.volatile = {}
    p.status = nil
end

function BattleEngine:speedOf(p)
    local spe = p.stats.spe
    if p.status == "paralysis" then spe = math.floor(spe / 4) end
    local mult = self.stageMultiplier(clampStage(p.stages.spe))
    return math.max(1, math.floor(spe * mult))
end

function BattleEngine.stageMultiplier(stage)
    if stage >= 0 then return (2 + stage) / 2 end
    return 2 / (2 - stage)
end

function BattleEngine:accuracyMultiplierOf(atk, def)
    local combined = clampStage(atk.stages.acc) - clampStage(def.stages.eva)
    if combined >= 0 then return (3 + combined) / 3 end
    return 3 / (3 - combined)
end

-- Apply a move from attacker to defender. Returns a result table.
function BattleEngine:useMove(attackerSide, moveIndex, defenderSide)
    defenderSide = defenderSide or self:opponentOf(attackerSide)
    local atk = self:active(attackerSide)
    local def = self:active(defenderSide)
    local result = { hit = false, damage = 0, ko = false, immune = false, missed = false }

    if self.over then return result end
    if not atk or atk.fainted then return result end
    if not def or def.fainted then return result end

    local moveSlot = atk.moves[moveIndex]
    local move, moveName
    if not moveSlot or moveSlot.pp <= 0 or moveSlot.disabled then
        -- Struggle when no usable move remains
        local anyUsable = false
        for _, m in ipairs(atk.moves) do
            if m.pp > 0 and not m.disabled then anyUsable = true break end
        end
        if not anyUsable then
            self:logMsg(atk.name .. " has no moves left! It used Struggle!")
            move = BattleEngine.STRUGGLE
            moveName = "Struggle"
        else
            self:logMsg(atk.name .. " can't use that move!")
            return result
        end
    else
        move = Moves.get(moveSlot.id)
        moveName = Moves.displayName(moveSlot.id)
        moveSlot.pp = moveSlot.pp - 1
    end

    -- Status checks that skip the turn
    if atk.status == "sleep" then
        atk.volatile.sleepTurns = (atk.volatile.sleepTurns or 0) + 1
        if atk.volatile.sleepTurns <= (atk.volatile.sleepMax or 2) then
            self:logMsg(atk.name .. " is fast asleep!")
            return result
        end
        atk.status = nil
        atk.volatile.sleepTurns = nil
        self:logMsg(atk.name .. " woke up!")
    elseif atk.status == "freeze" then
        if self.rng:chance(20) then
            atk.status = nil
            self:logMsg(atk.name .. " thawed out!")
        else
            self:logMsg(atk.name .. " is frozen solid!")
            return result
        end
    elseif atk.status == "paralysis" then
        if self.rng:chance(25) then
            self:logMsg(atk.name .. " is fully paralyzed! It can't move!")
            return result
        end
    elseif atk.status == "confusion" then
        atk.volatile.confusionTurns = (atk.volatile.confusionTurns or 0) + 1
        if atk.volatile.confusionTurns > (atk.volatile.confusionMax or 2) then
            atk.status = nil
            atk.volatile.confusionTurns = nil
            self:logMsg(atk.name .. " snapped out of its confusion!")
        else
            self:logMsg(atk.name .. " is confused!")
            if self.rng:chance(50) then
                local dmg = self:calcDamage(atk, atk, { type = "Normal", cat = "physical", power = 40 })
                atk.hp = math.max(0, atk.hp - dmg)
                self:logMsg("It hurt itself in its confusion! (" .. dmg .. " damage)")
                result.hit = true
                result.damage = dmg
                result.selfHit = true
                if atk.hp <= 0 then result.ko = true end
                return result
            end
        end
    end

    if atk.volatile.flinch then
        atk.volatile.flinch = nil
        self:logMsg(atk.name .. " flinched!")
        return result
    end

    self:logMsg(atk.name .. " used " .. moveName .. "!")
    atk.lastMoveType = (move.cat or Types.categoryFor(move.type))

    -- Two-turn moves
    if move.twoTurn then
        if atk.volatile.charging == move.twoTurn then
            atk.volatile.charging = nil
        else
            atk.volatile.charging = move.twoTurn
            self:logMsg(atk.name .. " is charging up!")
            return result
        end
    end

    -- Accuracy check
    local acc = move.acc or 100
    if acc < 100 then
        local accMult = self:accuracyMultiplierOf(atk, def)
        if not self.rng:chance(math.min(100, acc * accMult)) then
            self:logMsg("But it missed!")
            result.missed = true
            if move.effect and move.effect.missCrash then
                local crash = math.max(1, math.floor(self:calcDamage(atk, atk, move) / 2))
                atk.hp = math.max(0, atk.hp - crash)
                self:logMsg(atk.name .. " kept going and crashed! (" .. crash .. " damage)")
                result.damage = crash
                result.selfHit = true
                if atk.hp <= 0 then result.ko = true end
            end
            return result
        end
    end

    -- Status moves
    if (move.cat or Types.categoryFor(move.type)) == "status" or move.power == 0 then
        result.hit = true
        self:applyStatusMove(atk, def, move, result)
        return result
    end

    -- Immunity
    local mult = Types.getEffectivenessVs(move.type, def.types[1], def.types[2])
    if mult == 0 then
        self:logMsg("It doesn't affect " .. def.name .. "...")
        result.immune = true
        return result
    end

    -- Multi-hit moves (Gen 1: 2-5 hits for {2,5} moves, fixed count otherwise)
    local hitCount = 1
    if move.hits then
        if type(move.hits) == "table" then
            -- Gen 1 distribution for 2-5 hit moves: 2 hits 3/8, 3 hits 3/8,
            -- 4 hits 1/8, 5 hits 1/8
            local roll = self.rng:nextFloat()
            if roll < 0.375 then hitCount = 2
            elseif roll < 0.75 then hitCount = 3
            elseif roll < 0.875 then hitCount = 4
            else hitCount = 5 end
        else
            hitCount = move.hits
        end
    end

    local totalDamage = 0
    for hit = 1, hitCount do
        local damage = self:calcDamage(atk, def, move)
        totalDamage = totalDamage + damage
        -- Substitute absorbs the hit
        if def.volatile.substitute and damage > 0 then
            def.volatile.substitute = def.volatile.substitute - damage
            if def.volatile.substitute <= 0 then
                def.volatile.substitute = nil
                self:logMsg(def.name .. "'s substitute broke!")
            else
                self:logMsg(def.name .. "'s substitute took the hit! (" .. damage .. ")")
            end
            def.lastDamageTaken = 0
        else
            def.hp = math.max(0, def.hp - damage)
            def.lastDamageTaken = damage
        end
        if def.hp <= 0 then break end
    end
    result.hit = true
    result.damage = totalDamage

    local effText = ""
    if mult >= 2 then effText = " It's super effective!"
    elseif mult > 0 and mult < 1 then effText = " It's not very effective..." end
    if hitCount > 1 then
        self:logMsg("It hit " .. hitCount .. " times! It dealt " .. totalDamage .. " damage!" .. effText)
    else
        self:logMsg("It dealt " .. totalDamage .. " damage!" .. effText)
    end

    if self._lastCrit then
        self:logMsg("A critical hit!")
    end
    self._lastCrit = nil

    if move.effect then
        self:applyEffect(atk, def, move, totalDamage, result)
    end

    if def.hp <= 0 then result.ko = true end
    return result
end

-- Gen 1 damage formula (simplified):
--   dmg = floor(floor(floor(2*level/5 + 2) * power * A / D) / 50) + 2
--   then STAB (x1.5), type effectiveness, crit (x2), random 217-255/255
function BattleEngine:calcDamage(atk, def, move)
    local level = atk.level
    local power = move.power or 0

    -- Fixed damage moves
    if move.fixed == "level" then return level end
    if move.fixed == 40 then return 40 end
    if move.fixed == 20 then return 20 end
    if move.fixed == "half" then return math.max(1, math.floor(def.hp / 2)) end
    -- OHKO moves (Horn Drill, Fissure): KO on hit if user's level >= target's
    if move.fixed == "ohko" then
        if atk.level >= def.level then return def.hp end
        return 0
    end
    if move.fixed == "counter" then
        local taken = def.lastDamageTaken or 0
        if taken <= 0 or def.lastMoveType ~= "physical" then return 0 end
        return taken * 2
    end
    if power <= 0 then return 0 end

    local cat = move.cat or Types.categoryFor(move.type)
    local isPhysical = cat == "physical"
    local a = isPhysical and atk.stats.atk or atk.stats.spa
    local d = isPhysical and def.stats.def or def.stats.spd

    a = math.max(1, math.floor(a * self.stageMultiplier(clampStage(atk.stages.atk or 0))))
    d = math.max(1, math.floor(d * self.stageMultiplier(clampStage(def.stages.def or 0))))
    if atk.status == "burn" and isPhysical then a = math.max(1, math.floor(a / 2)) end

    -- Reflect / Light Screen halve damage on their respective category
    if def.volatile.reflect and isPhysical then d = d * 2 end
    if def.volatile.lightScreen and not isPhysical then d = d * 2 end

    local base = math.floor(math.floor(math.floor(2 * level / 5 + 2) * power * a / math.max(1, d)) / 50) + 2

    local stab = 1
    if atk.types[1] == move.type or atk.types[2] == move.type then stab = 1.5 end

    local eff = Types.getEffectivenessVs(move.type, def.types[1], def.types[2])

    -- Critical hit: Gen 1 uses base speed / 512 (highCrit doubles)
    local critChance = atk.stats.spe / 512
    if move.highCrit then critChance = critChance * 2 end
    if atk.volatile.focusEnergy then critChance = critChance * 4 end
    local crit = self.rng:chance(math.min(100, critChance * 100)) and 2 or 1
    if crit == 2 then self._lastCrit = true end

    local rand = 217 + math.floor(self.rng:nextFloat() * 39)

    local damage = math.floor(base * stab * eff * crit * rand / 255)
    if damage < 1 then damage = 1 end
    return damage
end

function BattleEngine:applyStatusMove(atk, def, move, result)
    local eff = move.effect or {}
    if eff.status then
        if def.status then
            self:logMsg("But it failed!")
            return
        end
        -- Ghosts can't be put to sleep (Gen 1)
        if eff.status == "sleep" and (def.types[1] == "Ghost" or def.types[2] == "Ghost") then
            self:logMsg("But it failed!")
            return
        end
        def.status = eff.status
        if eff.status == "sleep" then
            def.volatile.sleepTurns = 0
            def.volatile.sleepMax = self.rng:nextInt(1, 3)
        elseif eff.status == "confusion" then
            def.volatile.confusionTurns = 0
            def.volatile.confusionMax = self.rng:nextInt(1, 4)
        end
        self:logMsg(def.name .. " was " .. BattleEngine.statusVerb(eff.status) .. "!")
    end
    if eff.toxic then
        if def.status then
            self:logMsg("But it failed!")
            return
        end
        def.status = "poison"
        def.volatile.toxic = true
        self:logMsg(def.name .. " was badly poisoned!")
    end
    if eff.boost then
        local stat = eff.boost.stat
        local stages = eff.boost.stages
        local target = (stages < 0) and def or atk
        local cur = target.stages[stat] or 0
        if (stages > 0 and cur < 6) or (stages < 0 and cur > -6) then
            target.stages[stat] = clampStage(cur + stages)
            self:logMsg(target.name .. "'s " .. stat .. " " .. (stages > 0 and "rose" or "fell") .. "!")
        else
            self:logMsg("But it failed!")
        end
    end
    if eff.heal then
        local amount = math.floor(atk.maxHp * eff.heal)
        atk.hp = math.min(atk.maxHp, atk.hp + amount)
        self:logMsg(atk.name .. " regained health!")
    end
    if eff.rest then
        atk.hp = atk.maxHp
        atk.status = "sleep"
        atk.volatile.sleepTurns = 0
        atk.volatile.sleepMax = 2
        self:logMsg(atk.name .. " went to sleep and became healthy!")
    end
    if eff.haze then
        for _, p in ipairs({ atk, def }) do
            p.stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0, eva = 0 }
        end
        self:logMsg("All stat changes were eliminated!")
    end
    if eff.focusEnergy then
        atk.volatile.focusEnergy = true
        self:logMsg(atk.name .. " is getting pumped!")
    end
    if eff.lightScreen then
        atk.volatile.lightScreen = true
        self:logMsg("A light screen made " .. atk.name .. "'s side stronger!")
    end
    if eff.reflect then
        atk.volatile.reflect = true
        self:logMsg(atk.name .. "'s side is protected by Reflect!")
    end
    if eff.mist then
        atk.volatile.mist = true
        self:logMsg(atk.name .. " shrouded itself in Mist!")
    end
    if eff.disable then
        if #def.moves > 0 then
            local idx = self.rng:nextInt(1, #def.moves)
            def.moves[idx].disabled = true
            self:logMsg(def.name .. "'s " .. def.moves[idx].id .. " was disabled!")
        end
    end
    if eff.leechSeed then
        if def.volatile.leechSeed or def.types[1] == "Grass" or def.types[2] == "Grass" then
            self:logMsg("But it failed!")
            return
        end
        def.volatile.leechSeed = true
        self:logMsg(def.name .. " was seeded!")
    end
    if eff.transform then
        atk.volatile.transformed = def.species.id
        atk.types = { def.types[1], def.types[2] }
        atk.stats = {
            hp = atk.stats.hp,
            atk = def.stats.atk, def = def.stats.def,
            spa = def.stats.spa, spd = def.stats.spd, spe = def.stats.spe,
        }
        self:logMsg(atk.name .. " transformed into " .. def.name .. "!")
    end
    if eff.splash then
        self:logMsg("But nothing happened!")
    end
    if eff.whirlwind then
        result.forceSwitch = true
    end
    if eff.substitute then
        local cost = math.floor(atk.maxHp / 4)
        if atk.hp <= cost or atk.volatile.substitute then
            self:logMsg("But it failed!")
            return
        end
        atk.hp = atk.hp - cost
        atk.volatile.substitute = cost
        self:logMsg(atk.name .. " put up a substitute!")
    end
    if eff.metronome then
        local allMoves = {}
        for id in pairs(Moves.list) do allMoves[#allMoves + 1] = id end
        local picked = allMoves[self.rng:nextInt(1, #allMoves)]
        self:logMsg(atk.name .. " used Metronome and called " .. picked .. "!")
        local fake = Moves.get(picked)
        if fake and (fake.cat or Types.categoryFor(fake.type)) ~= "status" then
            local mult = Types.getEffectivenessVs(fake.type, def.types[1], def.types[2])
            if mult > 0 then
                local dmg = self:calcDamage(atk, def, fake)
                def.hp = math.max(0, def.hp - dmg)
                self:logMsg("It dealt " .. dmg .. " damage!")
            end
        end
    end
end

function BattleEngine.statusVerb(status)
    return ({
        burn = "burned", poison = "poisoned", paralysis = "paralyzed",
        sleep = "put to sleep", freeze = "frozen", confusion = "confused",
    })[status] or status
end

function BattleEngine:applyEffect(atk, def, move, damage, result)
    local eff = move.effect
    if not eff then return end

    if eff.drain and damage > 0 then
        local heal = math.max(1, math.floor(damage * eff.drain))
        atk.hp = math.min(atk.maxHp, atk.hp + heal)
        self:logMsg(atk.name .. " absorbed " .. heal .. " HP!")
    end
    if eff.recoil and damage > 0 then
        local recoil = math.max(1, math.floor(damage * eff.recoil))
        atk.hp = math.max(0, atk.hp - recoil)
        self:logMsg(atk.name .. " was hurt by recoil! (" .. recoil .. " damage)")
        if atk.hp <= 0 then result.ko = true end
    end
    if eff.status and self.rng:chance(eff.statusChance or 100) then
        if not def.status and not def.fainted then
            if not (eff.status == "sleep" and (def.types[1] == "Ghost" or def.types[2] == "Ghost")) then
                def.status = eff.status
                if eff.status == "confusion" then
                    def.volatile.confusionTurns = 0
                    def.volatile.confusionMax = self.rng:nextInt(1, 4)
                end
                self:logMsg(def.name .. " was " .. BattleEngine.statusVerb(eff.status) .. "!")
            end
        end
    end
    if eff.boost and self.rng:chance(eff.boostChance or 100) then
        local stat = eff.boost.stat
        local target = (eff.boost.stages < 0) and def or atk
        local cur = target.stages[stat] or 0
        target.stages[stat] = clampStage(cur + eff.boost.stages)
        self:logMsg(target.name .. "'s " .. stat .. " " .. (eff.boost.stages > 0 and "rose" or "fell") .. "!")
    end
    if eff.flinchChance and self.rng:chance(eff.flinchChance) then
        if self:speedOf(atk) > self:speedOf(def) then
            def.volatile.flinch = true
        end
    end
end

-- End-of-turn residual damage (burn/poison/leech seed)
function BattleEngine:applyResidual()
    for side = 1, 2 do
        local p = self:active(side)
        if p and not p.fainted then
            if p.status == "burn" then
                local dmg = math.max(1, math.floor(p.maxHp / 16))
                p.hp = math.max(0, p.hp - dmg)
                self:logMsg(p.name .. " was hurt by its burn! (" .. dmg .. ")")
            elseif p.status == "poison" then
                local dmg
                if p.volatile.toxic then
                    p.volatile.toxicCount = (p.volatile.toxicCount or 1) + 1
                    dmg = math.max(1, math.floor(p.maxHp / 16 * p.volatile.toxicCount))
                else
                    dmg = math.max(1, math.floor(p.maxHp / 16))
                end
                p.hp = math.max(0, p.hp - dmg)
                self:logMsg(p.name .. " was hurt by poison! (" .. dmg .. ")")
            end
            if p.volatile.leechSeed and not p.fainted then
                local dmg = math.max(1, math.floor(p.maxHp / 16))
                p.hp = math.max(0, p.hp - dmg)
                local foe = self:active(self:opponentOf(side))
                if foe and not foe.fainted then
                    foe.hp = math.min(foe.maxHp, foe.hp + dmg)
                end
                self:logMsg("Leech Seed sapped " .. p.name .. "! (" .. dmg .. ")")
            end
        end
    end
end

-- Execute a full turn given choices for both sides.
-- choices: { [1] = {type="move", index=n} | {type="switch", index=n} | {type="forfeit"},
--            [2] = ... }
-- Returns true if the battle is over.
function BattleEngine:runTurn(choices)
    if self.over then return true end

    -- Forfeit
    for side = 1, 2 do
        local c = choices[side]
        if c and c.type == "forfeit" then
            self.over = true
            self.winner = self:opponentOf(side)
            self:logMsg(self.sides[side].name .. " forfeited! " .. self.sides[self.winner].name .. " won the battle!")
            return true
        end
    end

    self.turn = self.turn + 1
    self:logMsg("--- Turn " .. self.turn .. " ---")

    -- Hard turn cap: side with more total HP wins.
    if self.turn > BattleEngine.MAX_TURNS then
        local totalA, totalB = 0, 0
        for _, p in ipairs(self.sides[1].team) do totalA = totalA + p.hp end
        for _, p in ipairs(self.sides[2].team) do totalB = totalB + p.hp end
        self.over = true
        if totalA ~= totalB then
            self.winner = totalA > totalB and 1 or 2
        end
        self:logMsg("The battle went on too long! " ..
            (self.winner and (self.sides[self.winner].name .. " won by endurance!") or "It's a draw!"))
        return true
    end

    -- Switches happen before moves
    for side = 1, 2 do
        local c = choices[side]
        if c and c.type == "switch" then
            if not self:forceSwitch(side, c.index) then
                self:logMsg("Can't switch to that Pokemon!")
            end
        end
    end

    if checkFaints(self) then return true end

    -- Build the action queue (priority, then speed)
    local actions = {}
    for side = 1, 2 do
        local c = choices[side]
        local p = self:active(side)
        if (not c or c.type == "move") and p and not p.fainted then
            local idx = (c and c.index) or 1
            local priority = 0
            local slot = p.moves[idx]
            if slot then
                local mv = Moves.get(slot.id)
                priority = (mv and mv.priority) or 0
            end
            actions[#actions + 1] = { side = side, kind = "move", index = idx, priority = priority, speed = self:speedOf(p) }
        end
    end
    table.sort(actions, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        if a.speed ~= b.speed then return a.speed > b.speed end
        return a.side < b.side
    end)

    for _, act in ipairs(actions) do
        if self.over then break end
        local p = self:active(act.side)
        if p and not p.fainted then
            self:useMove(act.side, act.index)
        end
        if checkFaints(self) then break end
    end

    if not self.over then
        self:applyResidual()
        checkFaints(self)
    end

    -- Auto-switch for sides whose active fainted
    if not self.over then
        for side = 1, 2 do
            if self.awaitingSwitch[side] then
                self:autoSwitch(side)
                self.awaitingSwitch[side] = nil
            end
        end
    end

    return self.over
end

return BattleEngine
