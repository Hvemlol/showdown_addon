local Net = {}

local Json = require("Core.Libs.Json")

Net.PREFIX = "SHOWDOWN_CLONE"
Net.CHANNEL = "PARTY" -- falls back to "RAID" or whispers in the addon layer
Net.VERSION = 1

-- Message types
Net.MSG = {
    HELLO = "hello",       -- version handshake
    CHALLENGE = "challenge",
    CHALLENGE_RESP = "challenge_resp", -- accept/decline
    TEAM = "team",         -- team snapshot (sent by challenger on accept)
    START = "start",       -- seed + start signal
    CHOICE = "choice",     -- per-turn move/switch choice
    RESIGN = "resign",
    RESULT = "result",     -- final result echo for verification
    PING = "ping",
}

-- Encode a message into a string safe for WoW addon channels (prefix:json).
function Net.encode(msgType, payload)
    local msg = { t = msgType, v = Net.VERSION, d = payload or {} }
    return Net.PREFIX .. ":" .. Json.encode(msg)
end

-- Decode a raw addon message string. Returns msgType, payload, ok.
function Net.decode(raw)
    if type(raw) ~= "string" then return nil, nil, false end
    local body = raw:match("^" .. Net.PREFIX .. ":(.*)$")
    if not body then return nil, nil, false end
    local ok, msg = pcall(Json.decode, body)
    if not ok or type(msg) ~= "table" or not msg.t then return nil, nil, false end
    if msg.v ~= Net.VERSION then return nil, nil, false end
    return msg.t, msg.d, true
end

-- Build the messages a challenger sends.
function Net.buildChallenge(fromName, toName, teamSize)
    return Net.encode(Net.MSG.CHALLENGE, {
        from = fromName,
        to = toName,
        teamSize = teamSize or 6,
    })
end

function Net.buildChallengeResponse(fromName, toName, accepted, reason)
    return Net.encode(Net.MSG.CHALLENGE_RESP, {
        from = fromName,
        to = toName,
        accepted = accepted and true or false,
        reason = reason,
    })
end

function Net.buildStart(fromName, toName, seed, teamSnapshot)
    return Net.encode(Net.MSG.START, {
        from = fromName,
        to = toName,
        seed = seed,
        team = teamSnapshot,
    })
end

function Net.buildChoice(fromName, toName, turn, choice)
    return Net.encode(Net.MSG.CHOICE, {
        from = fromName,
        to = toName,
        turn = turn,
        choice = choice,
    })
end

function Net.buildResign(fromName, toName)
    return Net.encode(Net.MSG.RESIGN, { from = fromName, to = toName })
end

function Net.buildResult(fromName, toName, winner, turns)
    return Net.encode(Net.MSG.RESULT, {
        from = fromName,
        to = toName,
        winner = winner,
        turns = turns,
    })
end

function Net.buildHello(playerName)
    return Net.encode(Net.MSG.HELLO, { name = playerName })
end

return Net
