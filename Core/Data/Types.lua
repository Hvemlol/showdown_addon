local Types = {}

Types.list = {
    "Normal", "Fire", "Water", "Electric", "Grass", "Ice", "Fighting", "Poison",
    "Ground", "Flying", "Psychic", "Bug", "Rock", "Ghost", "Dragon",
}

Types.index = {}
for i, name in ipairs(Types.list) do Types.index[name] = i end

Types.CATEGORIES = {
    Normal = "physical", Fire = "special", Water = "special",
    Electric = "special", Grass = "special", Ice = "special",
    Fighting = "physical", Poison = "physical", Ground = "physical",
    Flying = "physical", Psychic = "special", Bug = "special",
    Rock = "physical", Ghost = "physical", Dragon = "special",
}

-- Gen 1 defensive chart with the era's quirks:
-- Bug super-effective against Poison, Poison super-effective against Bug,
-- Ghost has no effect on Psychic (the famous Gen 1 bug),
-- Ice is not very effective against Fire.
--[type] = { [defendingType] = multiplier }
local NONE, NV = 0, 0.5
local SE, RES = 2, 0.5

Types.chart = {
    Normal   = { Rock = RES, Ghost = NONE },
    Fire     = { Fire = RES, Water = NV, Grass = SE, Ice = SE, Bug = SE, Rock = NV, Dragon = RES },
    Water    = { Fire = SE, Water = RES, Grass = NV, Ground = SE, Rock = SE, Dragon = RES },
    Electric = { Water = SE, Electric = RES, Grass = RES, Ground = NONE, Flying = SE, Dragon = RES },
    Grass    = { Fire = NV, Water = SE, Grass = RES, Poison = NV, Ground = SE, Flying = NV, Bug = NV, Rock = SE, Dragon = RES },
    Ice      = { Fire = NV, Water = NV, Grass = SE, Ice = RES, Ground = SE, Flying = SE, Dragon = SE },
    Fighting = { Normal = SE, Ice = SE, Poison = NV, Flying = NV, Psychic = NV, Bug = RES, Rock = SE, Ghost = NONE },
    Poison   = { Grass = SE, Poison = RES, Ground = NV, Rock = NV, Ghost = RES, Bug = SE },
    Ground   = { Fire = SE, Electric = SE, Grass = NV, Poison = SE, Flying = NONE, Bug = RES, Rock = SE },
    Flying   = { Electric = NV, Grass = SE, Fighting = SE, Bug = SE, Rock = NV },
    Psychic  = { Fighting = SE, Poison = SE, Psychic = RES },
    Bug      = { Fire = NV, Grass = SE, Fighting = RES, Poison = SE, Flying = RES, Psychic = SE, Ghost = RES },
    Rock     = { Fire = SE, Ice = SE, Fighting = NV, Ground = NV, Flying = SE, Bug = SE },
    Ghost    = { Normal = NONE, Psychic = NONE, Ghost = SE },
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
