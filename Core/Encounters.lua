local Encounters = {}

local PokemonData = require("Core.Data.Pokemon")
local BattleEngine = require("Core.BattleEngine")
local Trainers = require("Core.Data.Trainers")
local Stats = require("Core.Stats")
local PRNG = require("Core.Util.PRNG")

-- Wild Pokemon pools by zone type. Each entry: { id, weight, minLv, maxLv }
Encounters.ZONES = {
    forest = {
        { id = 10, weight = 20, minLv = 2, maxLv = 5 },
        { id = 13, weight = 20, minLv = 2, maxLv = 5 },
        { id = 16, weight = 20, minLv = 2, maxLv = 6 },
        { id = 19, weight = 15, minLv = 3, maxLv = 6 },
        { id = 21, weight = 10, minLv = 3, maxLv = 7 },
        { id = 43, weight = 10, minLv = 4, maxLv = 8 },
        { id = 48, weight = 5,  minLv = 5, maxLv = 9 },
    },
    water = {
        { id = 72, weight = 25, minLv = 5, maxLv = 15 },
        { id = 60, weight = 20, minLv = 5, maxLv = 15 },
        { id = 98, weight = 15, minLv = 8, maxLv = 18 },
        { id = 116, weight = 15, minLv = 10, maxLv = 20 },
        { id = 129, weight = 15, minLv = 5, maxLv = 10 },
        { id = 118, weight = 10, minLv = 15, maxLv = 25 },
    },
    cave = {
        { id = 41, weight = 20, minLv = 5, maxLv = 12 },
        { id = 74, weight = 20, minLv = 8, maxLv = 15 },
        { id = 27, weight = 20, minLv = 8, maxLv = 15 },
        { id = 50, weight = 15, minLv = 10, maxLv = 20 },
        { id = 95, weight = 10, minLv = 15, maxLv = 30 },
        { id = 105, weight = 10, minLv = 15, maxLv = 25 },
        { id = 88, weight = 5, minLv = 10, maxLv = 20 },
    },
    mountain = {
        { id = 66, weight = 20, minLv = 10, maxLv = 20 },
        { id = 74, weight = 15, minLv = 12, maxLv = 22 },
        { id = 95, weight = 15, minLv = 18, maxLv = 30 },
        { id = 111, weight = 15, minLv = 20, maxLv = 35 },
        { id = 142, weight = 10, minLv = 25, maxLv = 40 },
        { id = 58, weight = 15, minLv = 15, maxLv = 25 },
        { id = 77, weight = 10, minLv = 20, maxLv = 30 },
    },
    powerplant = {
        { id = 81, weight = 30, minLv = 15, maxLv = 25 },
        { id = 100, weight = 30, minLv = 15, maxLv = 25 },
        { id = 82, weight = 20, minLv = 20, maxLv = 30 },
        { id = 101, weight = 15, minLv = 25, maxLv = 35 },
        { id = 25, weight = 5, minLv = 20, maxLv = 30 },
    },
    sea = {
        { id = 72, weight = 20, minLv = 20, maxLv = 35 },
        { id = 73, weight = 20, minLv = 25, maxLv = 40 },
        { id = 130, weight = 15, minLv = 30, maxLv = 45 },
        { id = 131, weight = 10, minLv = 30, maxLv = 45 },
        { id = 120, weight = 20, minLv = 20, maxLv = 35 },
        { id = 121, weight = 10, minLv = 30, maxLv = 40 },
        { id = 117, weight = 5, minLv = 35, maxLv = 45 },
    },
    mansion = {
        { id = 19, weight = 15, minLv = 15, maxLv = 25 },
        { id = 20, weight = 15, minLv = 20, maxLv = 30 },
        { id = 88, weight = 15, minLv = 20, maxLv = 30 },
        { id = 89, weight = 15, minLv = 25, maxLv = 35 },
        { id = 92, weight = 15, minLv = 20, maxLv = 30 },
        { id = 93, weight = 15, minLv = 25, maxLv = 35 },
        { id = 94, weight = 10, minLv = 30, maxLv = 40 },
    },
    -- Default fallback (city/outdoor generic)
    default = {
        { id = 16, weight = 25, minLv = 2, maxLv = 8 },
        { id = 19, weight = 20, minLv = 3, maxLv = 10 },
        { id = 21, weight = 15, minLv = 4, maxLv = 10 },
        { id = 52, weight = 15, minLv = 5, maxLv = 12 },
        { id = 39, weight = 10, minLv = 5, maxLv = 12 },
        { id = 96, weight = 10, minLv = 6, maxLv = 14 },
        { id = 133, weight = 5, minLv = 10, maxLv = 18 },
    },
}

Encounters.SHINY_CHANCE = 1 / 4096
Encounters.BALL_MODIFIERS = {
    pokeball = 1.0,
    greatball = 1.5,
    ultraball = 2.0,
    masterball = 255.0,
}

function Encounters.zoneForInstance(mapId)
    -- WoW map ids -> zone type. This table is a curated mapping; unknown maps
    -- fall back to "default".
    local map = {
        [1411] = "forest",   -- Kalimdor generic
        [1413] = "forest",   -- Barrens-ish
        [1415] = "mountain", -- Alterac-ish
        [1416] = "forest",   -- Thousand Needles-ish
        [1417] = "cave",     -- Ungoro-ish
        [1418] = "mountain", -- Silithus-ish
        [1419] = "mountain", -- Tanaris-ish
        [1420] = "forest",   -- Azshara-ish
        [1421] = "mountain", -- Felwood-ish
        [1422] = "water",    -- Ashenvale-ish (water edges)
        [1423] = "mansion",  -- Duskwood-ish
        [1424] = "water",    -- Wetlands-ish
        [1425] = "mountain", -- Badlands-ish
        [1426] = "mountain", -- Blasted Lands-ish
        [1427] = "powerplant", -- Searing Gorge-ish
        [1428] = "mountain", -- Burning Steppes-ish
        [1429] = "mountain", -- Western Plaguelands-ish
        [1430] = "mansion",  -- Ghostlands-ish
        [1431] = "mountain", -- Deadwind Pass-ish
        [1432] = "water",    -- Swamp of Sorrows-ish
        [1433] = "mountain", -- Elwynn-ish
        [1434] = "forest",   -- Durotar-ish
        [1435] = "forest",   -- Dustwallow-ish
        [1436] = "mountain", -- Loch Modan-ish
        [1437] = "mountain", -- Redridge-ish
        [1438] = "cave",     -- Deadmines-ish
        [1440] = "mansion",  -- Stranglethorn-ish
        [1441] = "mountain", -- Teldrassil-ish
        [1442] = "forest",   -- Darkshore-ish
        [1443] = "mountain", -- Barrens south-ish
        [1445] = "mountain", -- Stonetalon-ish
        [1446] = "water",    -- Desolace-ish
        [1447] = "mountain", -- Feralas-ish
        [1448] = "mountain", -- Thousand Needles
        [1449] = "mansion",  -- Razorfen-ish
        [1450] = "cave",     -- Scarlet Monastery-ish
        [1451] = "water",    -- Azshara crater-ish
        [1452] = "powerplant", -- Blackrock-ish
        [1454] = "mountain", -- Winterspring-ish
        [1455] = "mountain", -- Moonglade-ish
        [1456] = "mountain", -- Silithus
        [1457] = "mountain", -- Un'Goro
        [1458] = "cave",     -- Dire Maul-ish
        [1460] = "water",    -- Azuremyst-ish
        [1461] = "water",    -- Bloodmyst-ish
        [1462] = "water",    -- Eversong-ish
        [1463] = "mansion",  -- Ghostlands
        [1464] = "powerplant", -- Hellfire-ish
        [1465] = "mountain", -- Zangarmarsh-ish
        [1466] = "water",    -- Terokkar-ish
        [1467] = "mountain", -- Nagrand-ish
        [1468] = "mountain", -- Blade's Edge-ish
        [1469] = "mountain", -- Netherstorm-ish
        [1470] = "mountain", -- Shadowmoon-ish
        [1471] = "sea",      -- Shattrath-ish
        [1472] = "sea",      -- Quel'Danas-ish
        [1941] = "sea",      -- Eversong sea
        [1943] = "mountain", -- Azuremyst
        [1944] = "mountain", -- Hellfire Peninsula
        [1945] = "mountain", -- Zangarmarsh
        [1946] = "water",    -- Terokkar Forest
        [1948] = "mountain", -- Nagrand
        [1950] = "mountain", -- Blade's Edge
        [1951] = "mountain", -- Netherstorm
        [1952] = "mountain", -- Shadowmoon Valley
        [1954] = "sea",      -- Shattrath
        [1955] = "sea",      -- Isle of Quel'Danas
    }
    return map[mapId] or "default"
end

local function weightedPick(pool, rng)
    local total = 0
    for _, e in ipairs(pool) do total = total + e.weight end
    local roll = rng:nextFloat() * total
    local acc = 0
    for _, e in ipairs(pool) do
        acc = acc + e.weight
        if roll <= acc then return e end
    end
    return pool[#pool]
end

-- Generate a wild encounter. Returns { speciesId, level, shiny, instance }
function Encounters.generateWild(rng, zoneType, playerLevel)
    rng = rng or PRNG.new(PRNG.randomSeed())
    local pool = Encounters.ZONES[zoneType] or Encounters.ZONES.default
    local entry = weightedPick(pool, rng)
    local minLv = math.max(1, entry.minLv - 2)
    local maxLv = entry.maxLv + 2
    if playerLevel then
        maxLv = math.max(maxLv, math.min(playerLevel + 5, entry.maxLv + 5))
    end
    local level = rng:nextInt(minLv, maxLv)
    local shiny = rng:chance(Encounters.SHINY_CHANCE * 100)
    local ivs = Stats.randomIvs(rng)
    local pokemon = BattleEngine.newPokemon(entry.id, level, { ivs = ivs, shiny = shiny })
    return { pokemon = pokemon, zone = zoneType }
end

-- Catch attempt. ball: "pokeball"|"greatball"|"ultraball"|"masterball"
-- Returns { success, chance, shakes }
function Encounters.attemptCatch(rng, pokemon, ball, playerLevel)
    rng = rng or PRNG.new(PRNG.randomSeed())
    ball = ball or "pokeball"
    local ballMod = Encounters.BALL_MODIFIERS[ball] or 1.0
    if ball == "masterball" then
        return { success = true, chance = 1, shakes = 4 }
    end
    -- Catch formula (simplified Gen 1):
    --   rate = species catchRate (use (255 - maxBaseStat)) as proxy; min 3
    local b = pokemon.species.base
    local catchRate = math.max(3, 255 - math.max(b.hp, b.atk, b.def, b.spa, b.spe))
    local hpFactor = (pokemon.maxHp * 3 - pokemon.hp * 2) / (pokemon.maxHp * 3)
    hpFactor = math.max(0.05, math.min(1, hpFactor))
    local statusBonus = 1
    if pokemon.status == "sleep" or pokemon.status == "freeze" then statusBonus = 2
    elseif pokemon.status then statusBonus = 1.5 end
    local levelFactor = math.max(0.2, 1 - (pokemon.level - (playerLevel or pokemon.level)) * 0.05)
    local chance = (catchRate / 255) * hpFactor * statusBonus * ballMod * levelFactor
    chance = math.max(0.01, math.min(1, chance))
    local roll = rng:nextFloat()
    local shakes = 0
    local threshold = chance
    for i = 1, 4 do
        if roll < threshold then shakes = shakes + 1 else break end
        threshold = threshold ^ 0.75
    end
    local success = shakes >= 4
    if not success and rng:nextFloat() < 0.1 then success = false end
    return { success = success, chance = chance, shakes = shakes }
end

-- Generate a trainer battle team (list of Pokemon instances).
function Encounters.generateTrainer(rng, levelScale)
    rng = rng or PRNG.new(PRNG.randomSeed())
    local def = Trainers.generate(rng, { levelScale = levelScale })
    local team = {}
    for _, member in ipairs(def.team) do
        local ivs = Stats.randomIvs(rng)
        team[#team + 1] = BattleEngine.newPokemon(member.id, member.level, { ivs = ivs })
    end
    return { trainer = def, team = team }
end

-- Simple AI: pick the highest-damage move against the active foe.
-- Falls back to any move with PP (engine will Struggle) when none can damage.
function Encounters.aiChooseMove(battle, side)
    local p = battle:active(side)
    local foe = battle:active(battle:opponentOf(side))
    if not p or not foe then return { type = "move", index = 1 } end
    local Moves = require("Core.Data.Moves")
    local Types = require("Core.Data.Types")
    local best, bestDmg = 1, -1
    local anyDamaging = false
    for i, slot in ipairs(p.moves) do
        if slot.pp > 0 and not slot.disabled then
            local mv = Moves.get(slot.id)
            if mv and (mv.cat or Types.categoryFor(mv.type)) ~= "status" then
                anyDamaging = true
                local dmg = battle:calcDamage(p, foe, mv)
                if dmg > bestDmg then bestDmg, best = dmg, i end
            end
        end
    end
    if not anyDamaging then
        for i, slot in ipairs(p.moves) do
            if slot.pp > 0 then return { type = "move", index = i } end
        end
        return { type = "move", index = 1 } -- engine handles Struggle
    end
    return { type = "move", index = best }
end

return Encounters
