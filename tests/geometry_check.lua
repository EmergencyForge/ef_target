local harness = require('tests.harness')
local check = harness.check

harness.resetEFT()
harness.load('client/eft.lua')
harness.load('client/geometry.lua')
local G = EFT.Geometry

local box = { coords = vec3(10, 0, 0), size = vec3(4, 2, 2), rotation = 90.0 }
check('rotated box contains its long axis', G.inBox(box, vec3(10, 1.9, 0)))
check('rotated box drops the unrotated corner', not G.inBox(box, vec3(11.9, 0, 0)))
check('box ends above its height', not G.inBox(box, vec3(10, 0, 1.1)))

local sphere = { coords = vec3(0, 0, 0), radius = 2.0 }
check('sphere contains a close point', G.inSphere(sphere, vec3(1, 1, 1)))
check('sphere drops a far point', not G.inSphere(sphere, vec3(2, 1, 1)))

local poly = { points = { vec3(0, 0, 5), vec3(4, 0, 5), vec3(4, 4, 5), vec3(0, 4, 5) }, thickness = 2.0 }
check('poly contains the middle', G.inPoly(poly, vec3(2, 2, 5.9)))
check('poly ends above thickness', not G.inPoly(poly, vec3(2, 2, 6.1)))
check('poly ends below thickness', not G.inPoly(poly, vec3(2, 2, 3.9)))

-- U shape opening towards +Y, the notch is x 1..3, y 2..4
local concave = { thickness = 2.0, points = {
    vec3(0, 0, 5), vec3(4, 0, 5), vec3(4, 4, 5), vec3(3, 4, 5),
    vec3(3, 2, 5), vec3(1, 2, 5), vec3(1, 4, 5), vec3(0, 4, 5),
} }
check('concave poly leaves the notch out', not G.inPoly(concave, vec3(2, 3, 5)))
check('concave poly keeps its arm', G.inPoly(concave, vec3(0.5, 3, 5)))

local farZone = { coords = vec3(500, 500, 0), radius = 2.0 }
local nearZone = { coords = vec3(3, 0, 0), size = vec3(2, 2, 2) }
local g = G.grid(); g:add(G.prepare(farZone)); g:add(G.prepare(nearZone))
check('grid returns only close zones', #g:near(vec3(0, 0, 0), 10.0) == 1)

local wide = G.prepare({ coords = vec3(0, 0, 0), radius = 120.0 })
g:add(wide)
check('wide zone is listed once despite many cells', #g:near(vec3(0, 0, 0), 150.0) == 2)
g:remove(wide)
check('removed zone is gone', #g:near(vec3(0, 0, 0), 150.0) == 1)

check('prepare tags the kind', farZone.kind == 'sphere' and nearZone.kind == 'box' and G.prepare(poly).kind == 'poly')
check('poly hull covers every corner', poly.radius >= 2.83 and poly.center.x == 2)

harness.resetEFT()
