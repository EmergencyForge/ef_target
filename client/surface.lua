-- Draws the menu page as an upright surface in the world. It lies on the surface under the crosshair
-- when that faces the player well enough, otherwise it turns to the player once when placed.
local Surface = {}
EFT.Surface = Surface

local UP = vec3(0.0, 0.0, 1.0)
-- Metres per page pixel at REFERENCE metres. The size is set once on placing, closer menus come out smaller
-- so the text keeps roughly the same size on screen when it opens.
local METRES_PER_PIXEL = 0.0018
local REFERENCE, MIN_SIZE, MAX_SIZE = 2.5, 0.6, 1.6
-- Floors, tables and roofs would lay the text flat: steeper normals do not count as a surface
local STEEP = 0.7
-- Below this the surface is seen so much from the side that the text would be squashed, about 60 degrees
local GRAZING = 0.5
-- Pulls the surface towards the camera so curved bodywork and the bulk of a ped do not cover it.
-- Along the line of sight the point stays where it is on screen.
local LIFT = 0.15
-- How long the page keeps being drawn after hide, long enough for its fade and the press of a confirm
local FADE_MS = 450

local placed = nil
local visible, drawing, fadeUntil = false, false, 0

local function flat(v)
    local length = math.sqrt(v.x * v.x + v.y * v.y)
    if length < 0.0001 then return nil end
    return vec3(v.x / length, v.y / length, 0.0)
end

-- face points from the surface towards the viewer, right is the viewer's right on it
function Surface.orient(anchor, normal, camera)
    local face = flat(camera - anchor) or vec3(0.0, -1.0, 0.0)
    if normal and math.abs(normal.z) < STEEP then
        local onSurface = flat(normal)
        if onSurface and onSurface.x * face.x + onSurface.y * face.y >= GRAZING then face = onSurface end
    end
    return face, vec3(-face.y, face.x, 0.0)
end

-- Corners counter-clockwise as seen from the front: the game culls the back of a sprite poly.
-- UV 0,0 is the top left of the page.
function Surface.quad(centre, face, right, scale)
    local Nui = EFT.Nui
    local w = Nui.WIDTH / 2 * METRES_PER_PIXEL * scale * Config.MenuScale
    local h = w * Nui.HEIGHT / Nui.WIDTH
    local bl = centre - right * w - UP * h
    local br = centre + right * w - UP * h
    local tr = centre + right * w + UP * h
    local tl = centre - right * w + UP * h
    return {
        { bl, br, tr, { 0.0, 1.0 }, { 1.0, 1.0 }, { 1.0, 0.0 } },
        { bl, tr, tl, { 0.0, 1.0 }, { 1.0, 0.0 }, { 0.0, 0.0 } },
    }
end

-- Peds keep their turn to the player: a ped turning away would take the text with it
function Surface.place(anchor, normal, entity)
    if not anchor then return end
    local camera = GetFinalRenderedCamCoord()
    local isPed = entity and entity ~= 0 and GetEntityType(entity) == 1
    local face = Surface.orient(anchor, not isPed and normal or nil, camera)
    local distance = #(camera - anchor)
    local scale = math.max(MIN_SIZE, math.min(MAX_SIZE, distance / REFERENCE))
    placed = { anchor = anchor, face = face, scale = scale }
    if entity and entity ~= 0 then
        placed.entity = entity
        placed.offset = GetOffsetFromEntityGivenWorldCoords(entity, anchor.x, anchor.y, anchor.z)
        if not isPed then
            local tip = anchor + face
            placed.tip = GetOffsetFromEntityGivenWorldCoords(entity, tip.x, tip.y, tip.z)
        end
    end
end

-- Follows a moving entity, a vehicle also turns the surface with it
local function current()
    local p = placed
    if not p.entity or not DoesEntityExist(p.entity) then return p.anchor, p.face end
    local o = p.offset
    local anchor = GetOffsetFromEntityInWorldCoords(p.entity, o.x, o.y, o.z)
    if not p.tip then return anchor, p.face end
    local t = p.tip
    return anchor, flat(GetOffsetFromEntityInWorldCoords(p.entity, t.x, t.y, t.z) - anchor) or p.face
end

local function draw()
    local anchor, face = current()
    local toCamera = GetFinalRenderedCamCoord() - anchor
    local distance = #toCamera
    if distance > 0.0001 then anchor = anchor + toCamera * (math.min(LIFT, distance / 2) / distance) end
    for _, tri in ipairs(Surface.quad(anchor, face, vec3(-face.y, face.x, 0.0), placed.scale)) do
        local a, b, c = tri[1], tri[2], tri[3]
        DrawSpritePoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, 255, 255, 255, 255, EFT.Nui.TXD, EFT.Nui.TEXTURE,
            tri[4][1], tri[4][2], 1.0, tri[5][1], tri[5][2], 1.0, tri[6][1], tri[6][2], 1.0)
    end
end

-- Driven by the page: drawn while it shows and for its fade after
function Surface.visible(on)
    visible = on
    if not on then
        fadeUntil = GetGameTimer() + FADE_MS
        return
    end
    if drawing then return end
    drawing = true
    CreateThread(function()
        while placed and (visible or GetGameTimer() < fadeUntil) do
            draw()
            Wait(0)
        end
        drawing = false
    end)
end
