-- Plain Lua stand-in for the FiveM runtime. Tests load source files through harness.load,
-- stub natives through harness.natives and report with harness.check / harness.finish.
local harness = {}
local failed = 0

local vectorMeta = {}
local function vec3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end
vectorMeta.__add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end
vectorMeta.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
vectorMeta.__mul = function(a, b)
    if type(a) == 'number' then a, b = b, a end
    if type(b) == 'number' then return vec3(a.x * b, a.y * b, a.z * b) end
    return vec3(a.x * b.x, a.y * b.y, a.z * b.z)
end
vectorMeta.__len = function(v) return math.sqrt(v.x ^ 2 + v.y ^ 2 + v.z ^ 2) end
vectorMeta.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end

harness.vec3 = vec3
_G.vec3, _G.vector3 = vec3, vec3

-- Assigning an entry also makes it a global, the way FiveM natives are
harness.natives = setmetatable({}, {
    __newindex = function(t, name, fn)
        rawset(t, name, fn)
        _G[name] = fn
    end,
})

function harness.check(label, passed)
    print((passed and 'ok   ' or 'FAIL ') .. label)
    if not passed then failed = failed + 1 end
end

function harness.load(path)
    local chunk = assert(loadfile(path))
    return chunk()
end

function harness.resetEFT()
    EFT = {}
end

function harness.finish()
    return failed
end

return harness
