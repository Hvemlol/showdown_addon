local Serializer = {}

-- Serialize a Pokemon instance (see BattleEngine.newPokemon) to a plain table.
function Serializer.encodePokemon(p)
    local moves = {}
    for i, m in ipairs(p.moves) do
        moves[i] = { id = m.id, pp = m.pp }
    end
    return {
        id = p.id,
        level = p.level,
        exp = p.exp,
        ivs = { hp = p.ivs.hp, atk = p.ivs.atk, def = p.ivs.def, spa = p.ivs.spa, spd = p.ivs.spd, spe = p.ivs.spe },
        evs = { hp = p.evs.hp, atk = p.evs.atk, def = p.evs.def, spa = p.evs.spa, spd = p.evs.spd, spe = p.evs.spe },
        hp = p.hp,
        moves = moves,
        shiny = p.shiny and true or nil,
        nickname = p.nickname ~= p.species.name and p.nickname or nil,
    }
end

function Serializer.encodeTeam(team)
    local out = {}
    for i, p in ipairs(team) do
        out[i] = Serializer.encodePokemon(p)
    end
    return out
end

-- Rebuild a Pokemon instance from a serialized table. Requires BattleEngine
-- to be loadable; to avoid a hard dependency cycle we take it as an argument.
function Serializer.decodePokemon(t, BattleEngine, PokemonData)
    return BattleEngine.newPokemon(t.id, t.level, {
        ivs = t.ivs,
        evs = t.evs,
        exp = t.exp,
        moves = t.moves,
        shiny = t.shiny,
        nickname = t.nickname,
        hp = t.hp,
    })
end

function Serializer.decodeTeam(list, BattleEngine)
    local out = {}
    for i, t in ipairs(list) do
        out[i] = Serializer.decodePokemon(t, BattleEngine)
    end
    return out
end

return Serializer
