-- Draws the menu page as an upright surface in the world. Where it hangs and which way it faces come from
-- the object alone, never from where the crosshair hit: on the middle of the entity's side that faces the
-- player, or at a fixed point on that side. Only zones and free points, which have no entity, turn to the player.
local Surface = {}
EFT.Surface = Surface

local UP = vec3(0.0, 0.0, 1.0)
-- Metres per page pixel at REFERENCE metres. The size is set once on placing, closer menus come out smaller
-- so the text keeps roughly the same size on screen when it opens.
local METRES_PER_PIXEL = 0.0018
local REFERENCE, MIN_SIZE, MAX_SIZE = 2.5, 0.6, 1.6
-- Lifts the surface off the side it hangs on: mirrors, handles and a ped's arms reach past the model box
local LIFT = 0.10
-- How long the page keeps being drawn after hide, long enough for its fade and the press of a confirm
local FADE_MS = 450

local placed = nil
local visible, drawing, fadeUntil = false, false, 0

local function flat(v)
    local length = math.sqrt(v.x * v.x + v.y * v.y)
    if length < 0.0001 then return nil end
    return vec3(v.x / length, v.y / length, 0.0)
end

-- face points from the surface towards the viewer, right is the viewer's right on it.
-- With the entity's forward vector the face is whichever of its four sides looks most at the camera.
function Surface.orient(anchor, camera, forward)
    local toCamera = flat(camera - anchor) or vec3(0.0, -1.0, 0.0)
    local face = toCamera
    local f = forward and flat(forward)
    if f then
        local best = -2.0
        for _, side in ipairs({ f, f * -1.0, vec3(-f.y, f.x, 0.0), vec3(f.y, -f.x, 0.0) }) do
            local facing = side.x * toCamera.x + side.y * toCamera.y
            if facing > best then best, face = facing, side end
        end
    end
    return face, vec3(-face.y, face.x, 0.0)
end

-- The middle of the side of the model box that the camera looks at, and its outward axis, both in entity space.
-- The side is the one the line from the box centre to the camera leaves through, so a long vehicle keeps
-- showing its flank until the player stands nearly in front of it.
function Surface.boxSide(entity, camera)
    local min, max = GetModelDimensions(GetEntityModel(entity))
    local centre = (min + max) * 0.5
    local view = GetOffsetFromEntityGivenWorldCoords(entity, camera.x, camera.y, camera.z) - centre
    local halfX = math.max((max.x - min.x) * 0.5, 0.01)
    local halfY = math.max((max.y - min.y) * 0.5, 0.01)
    if math.abs(view.x) / halfX >= math.abs(view.y) / halfY then
        local sign = view.x >= 0 and 1.0 or -1.0
        return centre + vec3(sign * halfX, 0.0, 0.0), vec3(sign, 0.0, 0.0)
    end
    local sign = view.y >= 0 and 1.0 or -1.0
    return centre + vec3(0.0, sign * halfY, 0.0), vec3(0.0, sign, 0.0)
end

local function scaleAt(camera, anchor)
    return math.max(MIN_SIZE, math.min(MAX_SIZE, #(camera - anchor) / REFERENCE))
end

-- anchor is a fixed point (a bone, an offset, a zone marker) or nil to hang on the middle of the entity's side.
-- forward overrides the entity's facing for a point on a part that turns on its own, like a door.
-- A ped keeps the facing it got here: a ped turning away would take the text with it.
function Surface.place(anchor, entity, forward)
    local camera = GetFinalRenderedCamCoord()
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        if not anchor then return end
        placed = { anchor = anchor, face = Surface.orient(anchor, camera), scale = scaleAt(camera, anchor) }
        return
    end

    local offset, tip
    if anchor then
        offset = GetOffsetFromEntityGivenWorldCoords(entity, anchor.x, anchor.y, anchor.z)
        local t = anchor + Surface.orient(anchor, camera, forward or GetEntityForwardVector(entity))
        tip = GetOffsetFromEntityGivenWorldCoords(entity, t.x, t.y, t.z)
    else
        local axis
        offset, axis = Surface.boxSide(entity, camera)
        tip = offset + axis
        anchor = GetOffsetFromEntityInWorldCoords(entity, offset.x, offset.y, offset.z)
    end
    local face = flat(GetOffsetFromEntityInWorldCoords(entity, tip.x, tip.y, tip.z) - anchor) or Surface.orient(anchor, camera)
    placed = { anchor = anchor, face = face, scale = scaleAt(camera, anchor), entity = entity, offset = offset }
    if GetEntityType(entity) ~= 1 then placed.tip = tip end
end

-- Corners counter-clockwise as seen from the front: the game culls the back of a sprite poly.
-- UV 0,0 is the top left of the page.
function Surface.quad(centre, face, right, scale)
    local Nui = EFT.Nui
    local w = Nui.WIDTH / 2 * METRES_PER_PIXEL * scale * Config.MenuScale
    local h = w * Nui.HEIGHT / Nui.WIDTH
    local c = centre + face * LIFT
    local bl = c - right * w - UP * h
    local br = c + right * w - UP * h
    local tr = c + right * w + UP * h
    local tl = c - right * w + UP * h
    return {
        { bl, br, tr, { 0.0, 1.0 }, { 1.0, 1.0 }, { 1.0, 0.0 } },
        { bl, tr, tl, { 0.0, 1.0 }, { 1.0, 0.0 }, { 0.0, 0.0 } },
    }
end

-- Follows a moving entity, a vehicle or prop also turns the surface with it
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
