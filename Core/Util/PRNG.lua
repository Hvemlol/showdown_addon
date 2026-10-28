-- Deterministic PRNG (canonical mulberry32). Used for all battle RNG so that
-- PvP battles can be replayed identically on both clients from a shared seed.
-- Pure Lua 5.1 arithmetic (no bit library), safe for the WoW client.
local PRNG = {}
PRNG.__index = PRNG

local function bxor32(a, b)
    local r, p = 0, 1
    for _ = 0, 31 do
        local abit = a % (p * 2) >= p and 1 or 0
        local bbit = b % (p * 2) >= p and 1 or 0
        if abit ~= bbit then r = r + p end
        p = p * 2
    end
    return r
end

local function bor32(a, b)
    local r, p = 0, 1
    for _ = 0, 31 do
        local abit = a % (p * 2) >= p and 1 or 0
        local bbit = b % (p * 2) >= p and 1 or 0
        if abit == 1 or bbit == 1 then r = r + p end
        p = p * 2
    end
    return r
end

local function imul32(a, b)
    local p = (a * b) % 4294967296
    if p >= 2147483648 then p = p - 4294967296 end
    return p
end

local function shr32(a, n)
    return math.floor(a / 2 ^ n)
end

local function toUnsigned(x)
    return ((x % 4294967296) + 4294967296) % 4294967296
end

function PRNG.new(seed)
    local self = setmetatable({}, PRNG)
    self.state = math.floor(tonumber(seed) or 0) % 4294967296
    if self.state < 0 then self.state = self.state + 4294967296 end
    if self.state == 0 then self.state = 1 end
    return self
end

-- canonical mulberry32: returns a float in [0, 1)
function PRNG:nextFloat()
    self.state = (self.state + 0x6D2B79F5) % 4294967296
    local t = self.state
    t = imul32(bxor32(t, shr32(t, 15)), bor32(t, 1))
    t = bxor32(t, toUnsigned(t + imul32(bxor32(t, shr32(t, 7)), bor32(t, 61))))
    t = bxor32(t, shr32(t, 14))
    return toUnsigned(t) / 4294967296
end

-- integer in [min, max] inclusive
function PRNG:nextInt(min, max)
    if max < min then min, max = max, min end
    local span = max - min + 1
    return min + math.floor(self:nextFloat() * span) % span
end

-- returns true with probability percent/100
function PRNG:chance(percent)
    return self:nextFloat() * 100 < percent
end

function PRNG:seed()
    return self.state
end

-- Generate a random seed from wall clock; callers may override for tests.
function PRNG.randomSeed()
    local t = os and os.time and os.time() or 0
    local c = os and os.clock and math.floor(os.clock() * 1000) or 0
    return (t * 1000 + c) % 4294967296
end

return PRNG
