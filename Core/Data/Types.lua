local Types = {}

Types.list = {
    "Normal", "Fire", "Water", "Electric", "Grass", "Ice", "Fighting", "Poison",
    "Ground", "Flying", "Psychic", "Bug", "Rock", "Ghost", "Dragon",
}

Types.index = {}
for i, name in ipairs(Types.list) do Types.index[name] = i end

-- Gen 1 splits physical/special by move TYPE, not by move:
--   physical: Normal, Fighting, Poison, Ground, Flying, Bug, Rock, Ghost
--   special:  Fire, Water, Electric, Grass, Ice, Psychic, Dragon
Types.CATEGORIES = {
    Normal = "physical", Fire = "special", Water = "special",
    Electric = "special", Grass = "special", Ice = "special",
    Fighting = "physical", Poison = "physical", Ground = "physical",
    Flying = "physical", Psychic = "special", Bug = "physical",
    Rock = "physical", Ghost = "physical", Dragon = "special",
}

-- Gen 1 defensive chart (attacking type -> defending type -> multiplier)
-- with the era's quirks, matching Pokemon Showdown's gen1 mod:
--   Bug is super-effective against Poison AND Poison is super-effective
--   against Bug (Gen 1 only),
--   Ghost has no effect on Psychic (the famous Gen 1 bug),
--   Ice deals NEUTRAL damage to Fire (the 0.5x was introduced in Gen 2).
--[type] = { [defendingType] = multiplier }
local NONE, NV = 0, 0.5
local SE, RES = 2, 0.5

Types.chart = {
    Normal   = { Ghost = NONE, Rock = RES },
    Fire     = { Bug = SE, Dragon = RES, Fire = RES, Grass = SE, Ice = SE, Rock = RES, Water = RES },
    Water    = { Dragon = RES, Fire = SE, Grass = RES, Ground = SE, Rock = SE, Water = RES },
    Electric = { Dragon = RES, Electric = RES, Flying = SE, Grass = RES, Ground = NONE, Water = SE },
    Grass    = { Bug = RES, Dragon = RES, Fire = RES, Flying = RES, Grass = RES, Ground = SE, Poison = RES, Rock = SE, Water = SE },
    Ice      = { Dragon = SE, Flying = SE, Grass = SE, Ground = SE, Ice = RES, Water = RES },
    Fighting = { Bug = RES, Flying = RES, Ghost = NONE, Ice = SE, Normal = SE, Poison = RES, Psychic = RES, Rock = SE },
    Poison   = { Bug = SE, Ghost = RES, Grass = SE, Ground = RES, Poison = RES, Rock = RES },
    Ground   = { Bug = RES, Electric = SE, Fire = SE, Flying = NONE, Grass = RES, Poison = SE, Rock = SE },
    Flying   = { Bug = SE, Electric = RES, Fighting = SE, Grass = SE, Rock = RES },
    Psychic  = { Fighting = SE, Poison = SE, Psychic = RES },
    Bug      = { Fighting = RES, Fire = RES, Flying = RES, Ghost = RES, Grass = SE, Poison = SE, Psychic = SE },
    Rock     = { Bug = SE, Fighting = RES, Fire = SE, Flying = SE, Ground = RES, Ice = SE },
    Ghost    = { Ghost = SE, Normal = NONE, Psychic = NONE },
    Dragon   = { Dragon = SE },
}

function Types.getEffectiveness(attacking, defending)
    local row = Types.chart[attacking]
    if not row then return 1 end
    local mult = row[defending]
    if mult == nil then return 1 end
    return mult
end

function Types.getEffectivenessVs(attacking, type1, type2)
    local mult = Types.getEffectiveness(attacking, type1)
    if type2 and type2 ~= type1 then
        mult = mult * Types.getEffectiveness(attacking, type2)
    end
    return mult
end

Types.categoryFor = function(moveType)
    return Types.CATEGORIES[moveType] or "physical"
end

function Types.isValid(name)
    return Types.index[name] ~= nil
end

return Types
