local harness = require('tests.harness')
local check = harness.check
local natives = harness.natives

harness.resetEFT()
_G.Config = { MenuScale = 1.0 }
local camera = vec3(0, -3, 0)
local clock, threads, tris = 0, {}, {}
local entities = { [7] = { type = 2, coords = vec3(0, 0, 0) }, [8] = { type = 1, coords = vec3(0, 0, 0) } }
natives.GetFinalRenderedCamCoord = function() return camera end
natives.GetGameTimer = function() return clock end
natives.CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end
natives.Wait = function() coroutine.yield() end
natives.GetEntityType = function(entity) return entities[entity].type end
natives.DoesEntityExist = function(entity) return entities[entity] ~= nil end
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
local face, right = S.orient(origin, nil, camera)
check('without a surface the menu turns to the player', same(face, 0, -1, 0) and same(right, 1, 0, 0))
face = S.orient(origin, vec3(0.5, -0.866, 0), camera)
check('a wall facing the player carries the menu', same(face, 0.5, -0.866, 0))
face = S.orient(origin, vec3(1, 0, 0), camera)
check('a wall seen from the side falls back to the player', same(face, 0, -1, 0))
face = S.orient(origin, vec3(0.8, -0.6, 0), camera)
check('a wall at about 53 degrees still carries the menu', same(face, 0.8, -0.6, 0))
face = S.orient(origin, vec3(0.9, -0.436, 0), camera)
check('a wall past 60 degrees squashes the text, the menu turns to the player', same(face, 0, -1, 0))
face = S.orient(origin, vec3(0, -0.3, 0.95), camera)
check('a floor or table top does not lay the text flat', same(face, 0, -1, 0))
face = S.orient(origin, vec3(0, -0.6, 0.6), camera)
check('a tilted surface stands the menu upright', same(face, 0, -1, 0) and face.z == 0)

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
check('the page is centred on its anchor', near(tl.y, 0) and near(tl.x + br.x, 0))
check('one page pixel is 1.8 mm at full size', near(br.x - tl.x, 1024 * 0.0018))

-- Placing and drawing
S.place(vec3(0, 0, 0), vec3(1, 0, 0), 7)
S.visible(true)
local shown = frame()
check('a shown menu is drawn as two triangles', #shown == 2)
check('the menu stands 15 cm towards the camera', near(shown[1][1].y, -0.15))
camera = vec3(3, 0, 0)
local turned = frame()
check('the pull follows the camera, the menu keeps its own facing', same(centre(turned), 0.15, 0, 0) and near(turned[1][1].y, turned[1][2].y))
camera = vec3(0, -3, 0)
entities[7].coords = vec3(2, 0, 0)
local moved = frame()
check('the menu follows a moving vehicle', near(centre(moved).x, 2.0 - 0.15 * 2 / math.sqrt(13)))
S.place(vec3(0, 0, 0), vec3(0, -1, 0), 8)
entities[8].coords = vec3(0, 0, 0)
local onPed = frame()
check('a ped never lends its surface, the menu still faces the player', near(onPed[1][1].y, onPed[1][3].y))
S.place(vec3(0, 0, 0), nil, nil)
camera = vec3(0, -10, 0)
S.place(vec3(0, 0, 0), nil, nil)
local far = frame()
camera = vec3(0, -0.5, 0)
S.place(vec3(0, 0, 0), nil, nil)
local close = frame()
check('a far menu comes out bigger than a close one', (far[1][2].x - far[1][1].x) > (close[1][2].x - close[1][1].x))
S.visible(false)
check('a hidden menu stays for its fade', #frame() == 2)
clock = clock + 500
check('after the fade nothing is drawn', #frame() == 0 and #threads == 0)

for _, name in ipairs({ 'Config', 'GetFinalRenderedCamCoord', 'GetGameTimer', 'CreateThread', 'Wait', 'GetEntityType',
    'DoesEntityExist', 'GetOffsetFromEntityGivenWorldCoords', 'GetOffsetFromEntityInWorldCoords', 'DrawSpritePoly' }) do
    _G[name] = nil
end
