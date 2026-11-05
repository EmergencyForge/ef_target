-- Draws the markers as native sprites. NUI would trail the camera by a frame.
local Render = {}
EFT.Render = Render

local TXD = 'ef_target'
-- Fractions of screen width, height follows the aspect ratio so the sprites stay square
local AIM_WIDTH = 0.010
local POINT_SCALE = 0.7
local HIT_SCALE = 0.85
local HALO_SCALE = 1.8
local HALO_ALPHA = 0.9
local REST_ROTATION = 45.0
local HIT_ROTATION = 135.0

local points = {}
local aim = nil
local aimHit = false
local active = false
local threadAlive = false
local texturesReady = false
local texturesFailed = false
local aspect = 16 / 9

-- Rotation and fill follow the hit state, the halo grows from 0.6 to 1 as in the approved preview
local rotation = { value = REST_ROTATION, velocity = 0.0 }
local fill = { value = 0.0, velocity = 0.0 }
local halo = { value = 0.0, velocity = 0.0 }
local scale = { value = 1.0, velocity = 0.0 }

local function resetSprings()
    rotation.value, rotation.velocity = REST_ROTATION, 0.0
    fill.value, fill.velocity = 0.0, 0.0
    halo.value, halo.velocity = 0.0, 0.0
    scale.value, scale.velocity = 1.0, 0.0
end

-- A missing or unreadable PNG must not take the session down, so a failed load disables drawing for good
local function loadTextures()
    if texturesReady then return true end
    if texturesFailed then return false end
    local ok, err = pcall(function()
        local txd = CreateRuntimeTxd(TXD)
        for _, name in ipairs({ 'ring', 'fill', 'edge', 'halo' }) do
            if not CreateRuntimeTextureFromImage(txd, name, 'assets/' .. name .. '.png') then
                error('could not load assets/' .. name .. '.png')
            end
        end
    end)
    if not ok then
        texturesFailed = true
        print('[ef_target] marker textures failed to load, markers are disabled: ' .. tostring(err))
        return false
    end
    texturesReady = true
    return true
end

local function sprite(name, x, y, width, heading, r, g, b, a)
    DrawSprite(TXD, name, x, y, width, width * aspect, heading, r, g, b, a)
end

local function drawPoint()
    sprite('edge', 0.0, 0.0, AIM_WIDTH * POINT_SCALE, REST_ROTATION, 255, 255, 255, 255)
    sprite('ring', 0.0, 0.0, AIM_WIDTH * POINT_SCALE, REST_ROTATION, 255, 255, 255, 255)
end

local function drawAim(x, y, ar, ag, ab)
    local width = AIM_WIDTH * scale.value
    local f = fill.value
    if f < 0.0 then f = 0.0 elseif f > 1.0 then f = 1.0 end
    sprite('edge', x, y, width, rotation.value, 255, 255, 255, 255)
    -- The outline shifts to the accent as the diamond fills
    sprite('ring', x, y, width, rotation.value,
        math.floor(255 + (ar - 255) * f), math.floor(255 + (ag - 255) * f), math.floor(255 + (ab - 255) * f), 255)
    if f > 0.01 then sprite('fill', x, y, width, rotation.value, ar, ag, ab, math.floor(255 * f)) end
    local h = halo.value
    if h > 0.01 then
        if h > 1.0 then h = 1.0 end
        sprite('halo', x, y, AIM_WIDTH * HALO_SCALE * (0.6 + 0.4 * h), REST_ROTATION, ar, ag, ab,
            math.floor(255 * HALO_ALPHA * h))
    end
end

function Render.needsFrame()
    return active and (#points > 0 or aim ~= nil)
end

function Render.drawFrame()
    local dt = GetFrameTime()
    local Sp = EFT.Spring
    Sp.step(rotation, aimHit and HIT_ROTATION or REST_ROTATION, dt)
    Sp.step(fill, aimHit and 1.0 or 0.0, dt)
    Sp.step(halo, aimHit and 1.0 or 0.0, dt)
    Sp.step(scale, aimHit and HIT_SCALE or 1.0, dt)

    for _, point in ipairs(points) do
        -- The aimed point is drawn by the aim marker, two sprites would fight
        if not (aim and (aim == point or (point.key and point.key == aim.key))) then
            SetDrawOrigin(point.coords.x, point.coords.y, point.coords.z, 0)
            drawPoint()
            ClearDrawOrigin()
        end
    end

    if aim then
        local r, g, b = EFT.Accent.rgb()
        if aim.coords then
            SetDrawOrigin(aim.coords.x, aim.coords.y, aim.coords.z, 0)
            drawAim(0.0, 0.0, r, g, b)
            ClearDrawOrigin()
        else
            drawAim(0.5, 0.5, r, g, b)
        end
    end
end

local function wake()
    if threadAlive or not Render.needsFrame() then return end
    threadAlive = true
    -- The last session may have ended on a hit, the next aim must not ease back from it
    resetSprings()
    CreateThread(function()
        while Render.needsFrame() do
            Render.drawFrame()
            Wait(0)
        end
        threadAlive = false
    end)
end

-- Nearest points win, SetDrawOrigin allows 32 per frame and the aim marker needs one
function Render.setPoints(list)
    if not active then return end
    local sorted = {}
    for i, point in ipairs(list) do sorted[i] = point end
    table.sort(sorted, function(a, b) return (a.distance or 0) < (b.distance or 0) end)
    points = {}
    for i = 1, math.min(#sorted, Config.MaxPoints) do points[i] = sorted[i] end
    wake()
end

-- A point without coords aims at the screen centre
function Render.setAim(point, hit)
    aim = point
    aimHit = hit and true or false
    wake()
end

function Render.start()
    if not loadTextures() then return end
    -- The window can change size between sessions
    aspect = GetAspectRatio(false)
    resetSprings()
    EFT.Accent.push()
    active = true
    wake()
end

function Render.stop()
    active = false
    points, aim, aimHit = {}, nil, false
end

function Render.isRunning()
    return active
end
