-- Draws the markers as native sprites. NUI would trail the camera by a frame.
local Render = {}
EFT.Render = Render

local TXD = 'ef_target'
-- Fractions of screen width, height follows the aspect ratio so the sprites stay square
local AIM_WIDTH = 0.010
local POINT_SCALE = 0.7
local HIT_SCALE = 0.85
-- The square textures turn into diamonds when shown and back when hidden
local HEADING = 45.0
local FADE_END = 0.35 -- share of the turn after which a marker is fully visible
local GONE = 0.02
local COVERED = 0.2 -- a point hides once the marker has slid this close to it

-- Painted at runtime and not shipped as files, so the line width can come from the config
local SIZE = 64
local SAMPLES = 3
local TEXELS_PER_PIXEL = SIZE / (AIM_WIDTH * 1920)
local HALF = 22 -- half side of the square, leaves room for the outline inside the texture
local CORNER = 11 -- leg of a corner
local OUTLINE = 3
local OUTLINE_ALPHA = 0.6
local DOT = 3.5
local POINT_STROKE = 6
local FRAMES = 6 -- steps from the four corners to the closed diamond
local LINE, EDGE = 2, 1
local FRAME_NAMES = {}
for i = 0, FRAMES - 1 do FRAME_NAMES[i] = 'frame' .. i end

local points = {}
local aim = nil
local lastAim = nil -- aim is gone on release, the marker still has to turn away there
local aimHit = false
local active = false
local threadAlive = false
local texturesReady = false
local texturesFailed = false
local aspect = 16 / 9

local fill = { value = 0.0, velocity = 0.0 }
local scale = { value = 1.0, velocity = 0.0 }
-- Two springs: with near points on screen the own marker still has to turn in on its own
local aimTurn = { value = 0.0, velocity = 0.0 }
local pointTurn = { value = 0.0, velocity = 0.0 }
-- Runs from 1 to 0 after a new aim. The marker stays pinned to its target and only an offset eases out,
-- easing the position itself would make it trail the camera.
local slide = { value = 0.0, velocity = 0.0 }
local slideX, slideY = 0.0, 0.0
local lastId, lastX, lastY = nil, nil, nil

local function resetSprings()
    fill.value, fill.velocity = 0.0, 0.0
    scale.value, scale.velocity = 1.0, 0.0
    aimTurn.value, aimTurn.velocity = 0.0, 0.0
    pointTurn.value, pointTurn.velocity = 0.0, 0.0
    slide.value, slide.velocity = 0.0, 0.0
    lastId, lastX, lastY = nil, nil, nil
end

local function motion(turn)
    local alpha = turn.value / FADE_END
    if alpha < 0.0 then alpha = 0.0 elseif alpha > 1.0 then alpha = 1.0 end
    return HEADING * turn.value, alpha
end

-- shape(dx, dy) says what lies at that offset from the centre.
-- White lines and a black outline in one texture: the sprite tint colours the white and leaves the black.
local function paint(txd, name, shape)
    local texture = CreateRuntimeTexture(txd, name, SIZE, SIZE)
    if not texture then error('could not create texture ' .. name) end
    local total = SAMPLES * SAMPLES
    for y = 0, SIZE - 1 do
        for x = 0, SIZE - 1 do
            local line, edge = 0, 0
            for sy = 1, SAMPLES do
                for sx = 1, SAMPLES do
                    local kind = shape(x + (sx - 0.5) / SAMPLES - SIZE / 2, y + (sy - 0.5) / SAMPLES - SIZE / 2)
                    if kind == LINE then line = line + 1 elseif kind == EDGE then edge = edge + 1 end
                end
            end
            local weight = line + edge * OUTLINE_ALPHA
            local shade = weight > 0 and math.floor(255 * line / weight) or 0
            SetRuntimeTexturePixel(texture, x, y, shade, shade, shade, math.floor(255 * weight / total))
        end
    end
    CommitRuntimeTexture(texture)
end

-- gap is the half length of the opening in the middle of each side, 0 closes the frame
local function frameShape(stroke, gap, dot)
    return function(dx, dy)
        local ax, ay = math.abs(dx), math.abs(dy)
        local off, along = math.abs(math.max(ax, ay) - HALF), math.min(ax, ay)
        if off <= stroke / 2 and along >= gap then return LINE end
        local round = dot and math.sqrt(dx * dx + dy * dy)
        if round and round <= DOT then return LINE end
        if off <= stroke / 2 + OUTLINE and along >= gap - OUTLINE then return EDGE end
        if round and round <= DOT + OUTLINE then return EDGE end
    end
end

-- A failed paint must not take the session down, it disables drawing for good
local function loadTextures()
    if texturesReady then return true end
    if texturesFailed then return false end
    local ok, err = pcall(function()
        local reticle = Config.Reticle
        local stroke = math.max(1.0, math.min(reticle.Thickness, 3.5)) * TEXELS_PER_PIXEL
        local txd = CreateRuntimeTxd(TXD)
        paint(txd, 'fill', function(dx, dy) return math.max(math.abs(dx), math.abs(dy)) <= HALF and LINE or nil end)
        paint(txd, 'point', frameShape(POINT_STROKE, 0, false))
        for i = 0, FRAMES - 1 do
            paint(txd, FRAME_NAMES[i], frameShape(stroke, (HALF - CORNER) * (1 - i / (FRAMES - 1)), reticle.CenterDot))
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

local function drawPoint(heading, alpha)
    sprite('point', 0.0, 0.0, AIM_WIDTH * POINT_SCALE, heading, 255, 255, 255, math.floor(255 * alpha))
end

-- Fill runs from 0 to 1 with the hit: the corners grow into closed sides and the inside takes the accent
local function drawAim(x, y, ar, ag, ab)
    local width = AIM_WIDTH * scale.value
    local f = fill.value
    if f < 0.0 then f = 0.0 elseif f > 1.0 then f = 1.0 end
    local heading, alpha = motion(aimTurn)
    if f > 0.01 then sprite('fill', x, y, width, heading, ar, ag, ab, math.floor(255 * f * alpha)) end
    sprite(FRAME_NAMES[math.floor(f * (FRAMES - 1) + 0.5)], x, y, width, heading,
        math.floor(255 + (ar - 255) * f), math.floor(255 + (ag - 255) * f), math.floor(255 + (ab - 255) * f),
        math.floor(255 * alpha))
end

function Render.needsFrame()
    return (active and (#points > 0 or aim ~= nil)) or aimTurn.value > GONE or pointTurn.value > GONE
end

function Render.drawFrame()
    local dt = GetFrameTime()
    local Sp = EFT.Spring
    Sp.step(fill, aimHit and 1.0 or 0.0, dt)
    Sp.step(scale, aimHit and HIT_SCALE or 1.0, dt)
    Sp.step(aimTurn, aim and 1.0 or 0.0, dt)
    Sp.step(pointTurn, active and #points > 0 and 1.0 or 0.0, dt)

    local marked = (aim or aimTurn.value > GONE) and lastAim or nil
    local offsetX, offsetY = 0.0, 0.0
    if marked then
        local onScreen, x, y = true, 0.5, 0.5
        if marked.coords then
            onScreen, x, y = GetScreenCoordFromWorldCoord(marked.coords.x, marked.coords.y, marked.coords.z)
        end
        if onScreen then
            local id = marked.key or marked
            if id ~= lastId then
                if lastId then
                    slideX, slideY = lastX - x, lastY - y
                    slide.value, slide.velocity = 1.0, 0.0
                end
                lastId = id
            end
            Sp.step(slide, 0.0, dt)
            offsetX, offsetY = slideX * slide.value, slideY * slide.value
            lastX, lastY = x + offsetX, y + offsetY
        end
    end

    local covered = marked and slide.value < COVERED
    local heading, alpha = motion(pointTurn)
    for _, point in ipairs(points) do
        -- The aimed point is drawn by the aim marker, two sprites would fight
        if not point.offScreen and not (covered and (marked == point or (point.key and point.key == marked.key))) then
            SetDrawOrigin(point.coords.x, point.coords.y, point.coords.z, 0)
            drawPoint(heading, alpha)
            ClearDrawOrigin()
        end
    end

    if marked then
        local r, g, b = EFT.Accent.rgb()
        if marked.coords then
            SetDrawOrigin(marked.coords.x, marked.coords.y, marked.coords.z, 0)
            drawAim(offsetX, offsetY, r, g, b)
            ClearDrawOrigin()
        else
            drawAim(0.5 + offsetX, 0.5 + offsetY, r, g, b)
        end
    end
end

local function wake()
    if threadAlive or not Render.needsFrame() then return end
    threadAlive = true
    -- Only reached without a thread, so a press during the turn back keeps the springs where they are
    resetSprings()
    CreateThread(function()
        while Render.needsFrame() do
            Render.drawFrame()
            Wait(0)
        end
        threadAlive = false
        if not active then points = {} end
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
    lastAim = point or lastAim
    aimHit = hit and true or false
    wake()
end

function Render.start()
    if not loadTextures() then return end
    -- The window can change size between sessions
    aspect = GetAspectRatio(false)
    EFT.Accent.push()
    active = true
    wake()
end

-- The points stay in the list for the turn back, the render thread drops them when it ends
function Render.stop()
    active = false
    aim, aimHit = nil, false
end

function Render.isRunning()
    return active
end

-- Painting takes a moment, so it happens while the client loads and not on the first key press
CreateThread(loadTextures)
