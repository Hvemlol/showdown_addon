local Bot = {}

local BattleEngine = require("Core.BattleEngine")
local PokemonData = require("Core.Data.Pokemon")
local Moves = require("Core.Data.Moves")
local Types = require("Core.Data.Types")
local PRNG = require("Core.Util.PRNG")

-- Practice bot archetypes. Each has a name, a flavor line, and a fixed team
-- (species id, level, move list). Moves default to the species' 4 most
-- recent at that level when omitted.
Bot.TEAMS = {
    {
        name = "Youngster Joey",
        flavor = "My Rattata is in the top percentage of Rattata!",
        team = {
            { id = 19, level = 10 },
            { id = 16, level = 10 },
        },
    },
    {
        name = "Bug Catcher Don",
        flavor = "Bugs are tough!",
        team = {
            { id = 10, level = 15 },
            { id = 13, level = 15 },
            { id = 15, level = 18 },
        },
    },
    {
        name = "Lass Lassie",
        flavor = "I just like cute Pokemon!",
        team = {
            { id = 35, level = 20 },
            { id = 39, level = 20 },
            { id = 52, level = 22 },
        },
    },
    {
        name = "Hiker Henry",
        flavor = "Rocks! Gotta love 'em!",
        team = {
            { id = 74, level = 25 },
            { id = 27, level = 25 },
            { id = 95, level = 30 },
        },
    },
    {
        name = "Sailor Huey",
        flavor = "Anchors aweigh!",
        team = {
            { id = 56, level = 28 },
            { id = 54, level = 28 },
            { id = 98, level = 30 },
        },
    },
    {
        name = "Pokemaniac Ashton",
        flavor = "I want a rare Pokemon!",
        team = {
            { id = 113, level = 35 },
            { id = 105, level = 35 },
            { id = 143, level = 40 },
        },
    },
    {
        name = "Super Nerd Jovan",
        flavor = "I study Pokemon as a hobby!",
        team = {
            { id = 81, level = 38 },
            { id = 82, level = 40 },
            { id = 100, level = 40 },
            { id = 101, level = 42 },
        },
    },
    {
        name = "Blackbelt Kenji",
        flavor = "My fists are the strongest!",
        team = {
            { id = 66, level = 45 },
            { id = 67, level = 45 },
            { id = 68, level = 48 },
            { id = 106, level = 48 },
            { id = 107, level = 50 },
        },
    },
    {
        name = "Rocket Grunt",
        flavor = "Team Rocket blasts off at the speed of light!",
        team = {
            { id = 19, level = 45 },
            { id = 23, level = 45 },
            { id = 109, level = 48 },
            { id = 110, level = 50 },
        },
    },
    {
        name = "Cooltrainer Maya",
        flavor = "You'll never beat my balanced team!",
        team = {
            { id = 36, level = 55 },
            { id = 121, level = 55 },
            { id = 128, level = 58 },
            { id = 31, level = 58 },
            { id = 34, level = 60 },
        },
    },
    {
        name = "Gym Leader Brock",
        flavor = "My Rock Pokemon are impenetrable!",
        team = {
            { id = 74, level = 60 },
            { id = 75, level = 62 },
            { id = 95, level = 65 },
            { id = 76, level = 68 },
        },
    },
    {
        name = "Gym Leader Misty",
        flavor = "My Water Pokemon are tough!",
        team = {
            { id = 54, level = 60 },
            { id = 120, level = 62 },
            { id = 121, level = 65 },
            { id = 73, level = 68 },
        },
    },
    {
        name = "Gym Leader Lt.Surge",
        flavor = "Electric Pokemon shock!",
        team = {
            { id = 25, level = 60 },
            { id = 81, level = 62 },
            { id = 82, level = 65 },
            { id = 26, level = 68 },
        },
    },
    {
        name = "Gym Leader Erika",
        flavor = "The grass is strong!",
        team = {
            { id = 43, level = 60 },
            { id = 71, level = 62 },
            { id = 45, level = 65 },
            { id = 3, level = 68 },
        },
    },
    {
        name = "Gym Leader Sabrina",
        flavor = "Psychic power wins!",
        team = {
            { id = 64, level = 62 },
            { id = 122, level = 65 },
            { id = 63, level = 65 },
            { id = 65, level = 70 },
        },
    },
    {
        name = "Elite Four Lance",
        flavor = "Dragon Pokemon are invincible!",
        team = {
            { id = 148, level = 70 },
            { id = 149, level = 72 },
            { id = 147, level = 70 },
            { id = 142, level = 74 },
            { id = 149, level = 76 },
        },
    },
    {
        name = "Champion Blue",
        flavor = "The ultimate challenge!",
        team = {
            { id = 59, level = 80 },
            { id = 65, level = 80 },
            { id = 68, level = 82 },
            { id = 71, level = 82 },
            { id = 103, level = 84 },
            { id = 149, level = 88 },
        },
    },
}

-- Build a live team (Pokemon instances) from a bot definition.
function Bot.buildTeam(def)
    local team = {}
    for _, member in ipairs(def.team) do
        team[#team + 1] = BattleEngine.newPokemon(member.id, member.level, { moves = member.moves })
    end
    return team
end

function Bot.get(index)
    return Bot.TEAMS[((index - 1) % #Bot.TEAMS) + 1]
end

function Bot.count()
    return #Bot.TEAMS
end

-- Simple AI: pick the highest-damage move against the active foe.
-- Falls back to any move with PP (engine will Struggle) when none can damage.
function Bot.chooseMove(battle, side)
    local p = battle:active(side)
    local foe = battle:active(battle:opponentOf(side))
    if not p or not foe then return { type = "move", index = 1 } end
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
        return { type = "move", index = 1 }
    end
    return { type = "move", index = best }
end

-- Pick a random bot (optionally excluding the current one).
function Bot.random(rng, excludeIndex)
    rng = rng or PRNG.new(PRNG.randomSeed())
    local n = #Bot.TEAMS
    if n == 1 then return 1, Bot.TEAMS[1] end
    local idx
    repeat
        idx = rng:nextInt(1, n)
    until idx ~= excludeIndex
    return idx, Bot.TEAMS[idx]
end

return Bot
