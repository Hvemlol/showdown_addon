local Stats = {}

Stats.MAX_LEVEL = 100

-- Gen 1 stat calculation at max IV (15) and max EV (65535):
--   EV term: floor(sqrt(65535) / 4) = floor(255.998 / 4) = 63
--   HP  = floor(((base + 15) * 2 + 63) * level / 100) + level + 10
--       = floor((2 * base + 93) * level / 100) + level + 10
--   Other = floor((2 * base + 93) * level / 100) + 5
-- At L100: HP = 2*base + 203, others = 2*base + 98.
-- Gen 1 has a single "Special" stat, so spa == spd.
function Stats.calcStat(base, level, isHp)
    level = level or 1
    local stat = math.floor((2 * base + 93) * level / 100)
    if isHp then
        return stat + level + 10
    end
    return stat + 5
end

function Stats.computeStats(species, level)
    local b = species.base
    return {
        hp  = Stats.calcStat(b.hp,  level, true),
        atk = Stats.calcStat(b.atk, level),
        def = Stats.calcStat(b.def, level),
        spa = Stats.calcStat(b.spa, level),
        spd = Stats.calcStat(b.spd, level),
        spe = Stats.calcStat(b.spe, level),
    }
end

return Stats
