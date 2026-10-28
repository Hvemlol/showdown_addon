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

-- Approximate Pokemon type colors (RGB 0-1) used for UI accents/portraits.
-- These match the classic type color scheme used by the games and Showdown.
Types.COLORS = {
    Normal   = { 0.66, 0.63, 0.55 },
    Fire     = { 0.94, 0.55, 0.24 },
    Water    = { 0.27, 0.56, 0.93 },
    Electric = { 0.97, 0.82, 0.20 },
    Grass    = { 0.47, 0.79, 0.29 },
    Ice      = { 0.59, 0.85, 0.85 },
    Fighting = { 0.75, 0.19, 0.16 },
    Poison   = { 0.63, 0.25, 0.63 },
    Ground   = { 0.89, 0.75, 0.42 },
    Flying   = { 0.66, 0.56, 0.93 },
    Psychic  = { 0.94, 0.35, 0.54 },
    Bug      = { 0.65, 0.71, 0.13 },
    Rock     = { 0.71, 0.63, 0.24 },
    Ghost    = { 0.44, 0.35, 0.60 },
    Dragon   = { 0.44, 0.24, 0.97 },
}

-- Returns {r, g, b} for a type name (defaults to Normal gray).
function Types.color(typeName)
    return Types.COLORS[typeName] or Types.COLORS.Normal
end

-- Blends a type's color with a background color by `alpha` (0..1).
-- Useful for tinting portraits/bars. Returns {r, g, b}.
function Types.blend(typeName, alpha)
    local c = Types.color(typeName)
    alpha = math.max(0, math.min(1, alpha or 1))
    return { c[1] * alpha, c[2] * alpha, c[3] * alpha }
end

return Types
