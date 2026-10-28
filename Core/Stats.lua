local Stats = {}

Stats.MAX_LEVEL = 100
Stats.IV_MAX = 15
Stats.EV_MAX = 255

-- EXP needed to go from level L to L+1 (Gen 1 "medium fast" curve)
function Stats.expForLevel(level)
    if level >= Stats.MAX_LEVEL then return 0 end
    return math.floor(level ^ 3)
end

function Stats.totalExpForLevel(level)
    if level <= 1 then return 0 end
    local total = 0
    for l = 1, level - 1 do
        total = total + Stats.expForLevel(l)
    end
    return total
end

-- Gen 1 stat formula (simplified, no DVs affecting HP beyond the +base):
--   HP  = floor(((base + IV) * 2 + floor(sqrt(EV)/4)) * level / 100) + level + 10
--   Other = floor(((base + IV) * 2 + floor(sqrt(EV)/4)) * level / 100) + 5
function Stats.calcStat(base, iv, ev, level, isHp)
    iv = iv or Stats.IV_MAX
    ev = ev or 0
    level = level or 1
    local core = (base + iv) * 2 + math.floor(math.sqrt(math.min(ev, Stats.EV_MAX)) / 4)
    local stat = math.floor(core * level / 100)
    if isHp then
        return stat + level + 10
    end
    return stat + 5
end

-- Compute the full stat table for a species at a level.
-- ivs: optional {hp,atk,def,spa,spd,spe}; evs: optional same keys.
function Stats.computeStats(species, level, ivs, evs)
    ivs = ivs or {}
    evs = evs or {}
    local b = species.base
    return {
        hp  = Stats.calcStat(b.hp,  ivs.hp,  evs.hp,  level, true),
        atk = Stats.calcStat(b.atk, ivs.atk, evs.atk, level),
        def = Stats.calcStat(b.def, ivs.def, evs.def, level),
        spa = Stats.calcStat(b.spa, ivs.spa, evs.spa, level),
        spd = Stats.calcStat(b.spd, ivs.spd, evs.spd, level),
        spe = Stats.calcStat(b.spe, ivs.spe, evs.spe, level),
    }
end

-- Award EVs for defeating a Pokemon (Gen 1: each species has EV yield, 1-3 stats).
-- We use the classic Gen 1 EV yields (simplified to the primary stat).
Stats.EV_YIELD = {
    hp = 1, atk = 1, def = 1, spa = 1, spd = 1, spe = 1,
}

-- Deterministic pseudo-random IVs for wild Pokemon (0-15), via rng.
function Stats.randomIvs(rng)
    return {
        hp  = rng:nextInt(0, Stats.IV_MAX),
        atk = rng:nextInt(0, Stats.IV_MAX),
        def = rng:nextInt(0, Stats.IV_MAX),
        spa = rng:nextInt(0, Stats.IV_MAX),
        spd = rng:nextInt(0, Stats.IV_MAX),
        spe = rng:nextInt(0, Stats.IV_MAX),
    }
end

function Stats.addEvs(evs, defeatedSpecies)
    local b = defeatedSpecies.base
    -- award EVs proportional to the defeated Pokemon's highest base stats (up to 2)
    local keys = { "hp", "atk", "def", "spa", "spd", "spe" }
    local sorted = {}
    for _, k in ipairs(keys) do sorted[#sorted + 1] = { k = k, v = b[k] } end
    table.sort(sorted, function(a, b2) return a.v > b2.v end)
    for i = 1, math.min(2, #sorted) do
        local k = sorted[i].k
        evs[k] = math.min(Stats.EV_MAX, (evs[k] or 0) + 1)
    end
    return evs
end

return Stats
