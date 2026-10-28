local Serializer = {}

-- Serialize a Pokemon instance to a plain table.
-- A Showdown Pokemon is just: species + level + up to 4 moves.
function Serializer.encodePokemon(p)
    local moves = {}
    for i, m in ipairs(p.moves) do
        moves[i] = m.id
    end
    return {
        id = p.id,
        level = p.level,
        moves = moves,
        nickname = (p.nickname and p.nickname ~= p.species.name) and p.nickname or nil,
    }
end

function Serializer.encodeTeam(team)
    local out = {}
    for i, p in ipairs(team) do
        out[i] = Serializer.encodePokemon(p)
    end
    return out
end

-- Rebuild a Pokemon instance from a serialized table.
function Serializer.decodePokemon(t, BattleEngine)
    return BattleEngine.newPokemon(t.id, t.level, {
        moves = t.moves,
        nickname = t.nickname,
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
