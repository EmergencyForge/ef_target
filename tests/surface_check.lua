local harness = require('tests.harness')
local check = harness.check
local natives = harness.natives

harness.resetEFT()
_G.Config = { MenuScale = 1.0 }
local camera = vec3(0, -3, 0)
local clock, threads, tris = 0, {}, {}
local entities = {
    [7] = { type = 2, coords = vec3(0, 0, 0), model = 'car' },
    [8] = { type = 1, coords = vec3(0, 0, 0), model = 'ped' },
}
-- A car 2 m wide and 5 m long, a ped half a metre across
local boxes = { car = { vec3(-1, -2.5, -0.7), vec3(1, 2.5, 0.7) }, ped = { vec3(-0.3, -0.2, -1), vec3(0.3, 0.2, 0.9) } }
natives.GetFinalRenderedCamCoord = function() return camera end
natives.GetGameTimer = function() return clock end
natives.CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end
natives.Wait = function() coroutine.yield() end
natives.GetEntityType = function(entity) return entities[entity].type end
natives.GetEntityForwardVector = function(entity) return entities[entity].forward or vec3(0, 1, 0) end
natives.DoesEntityExist = function(entity) return entities[entity] ~= nil end
natives.GetEntityModel = function(entity) return entities[entity].model end
natives.GetModelDimensions = function(model) return boxes[model][1], boxes[model][2] end
natives.GetOffsetFromEntityGivenWorldCoords = function(entity, x, y, z) return vec3(x, y, z) - entities[entity].coords end
natives.GetOffsetFromEntityInWorldCoords = function(entity, x, y, z) return entities[entity].coords + vec3(x, y, z) end
natives.DrawSpritePoly = function(x1, y1, z1, x2, y2, z2, x3, y3, z3, _, _, _, _, _, _, u1, v1, _, u2, v2, _, u3, v3)
    tris[#tris + 1] = { vec3(x1, y1, z1), vec3(x2, y2, z2), vec3(x3, y3, z3), { u1, v1 }, { u2, v2 }, { u3, v3 } }
end
harness.load('client/eft.lua')
EFT.Nui = { WIDTH = 1024, HEIGHT = 512, TXD = 'ef_target_ui', TEXTURE = 'menu' }
harness.load('client/surface.lua')
local S = EFT.Surface

local function near(a, b) return math.abs(a - b) < 0.001 end
local function same(v, x, y, z) return near(v.x, x) and near(v.y, y) and near(v.z, z) end
local function pump()
    local batch = threads
    threads = {}
    for _, thread in ipairs(batch) do
        coroutine.resume(thread)
        if coroutine.status(thread) ~= 'dead' then threads[#threads + 1] = thread end
    end
end
local function frame()
    tris = {}
    pump()
    return tris
end
-- bl and tr of the first triangle are opposite corners
local function centre(drawn) return (drawn[1][1] + drawn[1][3]) * 0.5 end


-- Orientation
local origin = vec3(0, 0, 0)
local face, right = S.orient(origin, camera)
check('without an entity the menu turns to the player', same(face, 0, -1, 0) and same(right, 1, 0, 0))
local turned30 = vec3(0.5, 0.866, 0)
face = S.orient(origin, camera, turned30)
check('an entity lends the side that faces the player, not the camera direction', same(face, -0.5, -0.866, 0))
face = S.orient(origin, camera, vec3(1, 0, 0))
check('an entity seen from its flank lends its flank', same(face, 0, -1, 0))
face = S.orient(origin, camera, vec3(0.8, 0.6, 0))
check('the side changes only past the corner of the entity', same(face, 0.6, -0.8, 0))

-- The side of the model box
local offset, axis = S.boxSide(7, camera)
check('in front of a car the menu hangs on the middle of its nose', same(offset, 0, -2.5, 0) and same(axis, 0, -1, 0))
offset, axis = S.boxSide(7, vec3(3, -1, 0))
check('beside a car it hangs on the middle of its flank', same(offset, 1, 0, 0) and same(axis, 1, 0, 0))
offset = S.boxSide(7, vec3(1.5, -4, 0))
check('a long car keeps showing its flank until the player stands nearly in front', same(offset, 0, -2.5, 0))
offset = S.boxSide(7, vec3(2.5, -4, 0))
check('past the corner line the flank takes over', same(offset, 1, 0, 0))

-- Two triangles, counter-clockwise from the front, page top left at UV 0,0
local quad = S.quad(origin, vec3(0, -1, 0), vec3(1, 0, 0), 1.0)
local function towardsCamera(t)
    local a, b, c = t[1], t[2], t[3]
    local ux, uz, vx, vz = b.x - a.x, b.z - a.z, c.x - a.x, c.z - a.z
    -- Seen from -y with x to the right and z up, counter-clockwise has a positive cross product
    return ux * vz - uz * vx > 0
end
check('both triangles turn their front to the viewer', towardsCamera(quad[1]) and towardsCamera(quad[2]))
local tl, br = quad[2][3], quad[1][2]
check('the top left corner carries UV 0,0', tl.x < 0 and tl.z > 0 and quad[2][6][1] == 0.0 and quad[2][6][2] == 0.0)
check('the bottom right corner carries UV 1,1', br.x > 0 and br.z < 0 and quad[1][5][1] == 1.0 and quad[1][5][2] == 1.0)
check('the page keeps its aspect ratio', near((br.x - tl.x) / (tl.z - br.z), 2.0))
check('the surface sits 10 cm off what it lies on', near(tl.y, -0.10) and near(tl.x + br.x, 0))
check('one page pixel is 1.8 mm at full size', near(br.x - tl.x, 1024 * 0.0018))


-- Placing and drawing
S.place(nil, 7)
S.visible(true)
local shown = frame()
check('a shown menu is drawn as two triangles', #shown == 2)
check('an entity target hangs on the side facing the player, 10 cm out', same(centre(shown), 0, -2.6, 0))
camera = vec3(3, 0, 0)
check('a moving camera leaves the menu where it was placed', same(centre(frame()), 0, -2.6, 0))
camera = vec3(0, -3, 0)
entities[7].coords = vec3(2, 0, 0)
check('the menu follows a moving vehicle', same(centre(frame()), 2.0, -2.6, 0))
entities[7].coords = vec3(0, 0, 0)
entities[7].forward = vec3(1, 0, 0)
S.place(vec3(1, -1, 0.5), 7)
check('a fixed point keeps its place and takes the side of its entity', same(centre(frame()), 1, -1.1, 0.5))
-- An opened door: the bone faces 60 degrees off the car, the menu lies on the door
S.place(vec3(1, -1, 0.5), 7, vec3(-0.866, 0.5, 0))
local onDoor = frame()
local doorRight = onDoor[1][2] - onDoor[1][1]
check('a point on an opened door lines up with the door, not the car', near(doorRight.x * 0.5 + doorRight.y * 0.866, 0) and doorRight.y < -0.1)
entities[8].forward = vec3(0.5, 0.866, 0)
S.place(nil, 8)
local onPed = frame()
check('a ped gets the menu in front of its body, 10 cm out', same(centre(onPed), 0, -0.3, -0.05))
entities[8].forward = vec3(0, -1, 0)
local stillPed = frame()
check('a ped turning keeps the facing it had', near(stillPed[1][1].x, onPed[1][1].x) and near(stillPed[1][1].y, onPed[1][1].y))
S.place(vec3(0, 0, 0), nil)
camera = vec3(0, -10, 0)
S.place(vec3(0, 0, 0), nil)
local far = frame()
camera = vec3(0, -0.5, 0)
S.place(vec3(0, 0, 0), nil)
local close = frame()
check('a far menu comes out bigger than a close one', (far[1][2].x - far[1][1].x) > (close[1][2].x - close[1][1].x))
S.visible(false)
check('a hidden menu stays for its fade', #frame() == 2)
clock = clock + 500
check('after the fade nothing is drawn', #frame() == 0 and #threads == 0)

for _, name in ipairs({ 'Config', 'GetFinalRenderedCamCoord', 'GetGameTimer', 'CreateThread', 'Wait', 'GetEntityType', 'GetEntityForwardVector', 'GetEntityModel', 'GetModelDimensions',
    'DoesEntityExist', 'GetOffsetFromEntityGivenWorldCoords', 'GetOffsetFromEntityInWorldCoords', 'DrawSpritePoly' }) do
    _G[name] = nil
end
