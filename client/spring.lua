-- Damped spring for marker rotation, scale and colour. Lua drives it per frame because the markers are native sprites.
local Spring = {}
EFT.Spring = Spring

local STIFFNESS = 300.0
local DAMPING = 21.0
-- A hitch of a few frames must not blow the integration up
local MAX_DT = 0.05

function Spring.step(s, target, dt)
    if dt > MAX_DT then dt = MAX_DT end
    s.velocity = s.velocity + ((target - s.value) * STIFFNESS - s.velocity * DAMPING) * dt
    s.value = s.value + s.velocity * dt
    return s.value
end
