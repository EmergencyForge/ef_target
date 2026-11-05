local harness = require('tests.harness')
local check = harness.check
local natives = harness.natives

harness.resetEFT()
_G.Config = { MaxPoints = 24, Reticle = { Thickness = 2.0, CenterDot = true } }
_G.json = { encode = function(t) return t end }
local sent = {}
natives.SendNuiMessage = function(msg) sent[#sent + 1] = msg end
local exported = '#336699'
_G.exports = setmetatable({}, { __index = function()
    return { GetAccentColor = function() return exported end }
end })
local handlers = {}
natives.AddEventHandler = function(name, fn) handlers[name] = fn end
natives.CreateRuntimeTxd = function() return 1 end
-- textures[name][y * 64 + x] = alpha, shade is kept next to it
local textures, committed, current = {}, {}, nil
natives.CreateRuntimeTexture = function(_, name) current = { name = name, alpha = {}, shade = {} }; textures[name] = current; return current end
natives.SetRuntimeTexturePixel = function(t, x, y, r, _, _, a) t.alpha[y * 64 + x] = a; t.shade[y * 64 + x] = r end
natives.CommitRuntimeTexture = function(t) committed[t.name] = true end
natives.GetAspectRatio = function() return 16 / 9 end
natives.GetScreenCoordFromWorldCoord = function() return true, 0.7, 0.5 end
natives.GetFrameTime = function() return 1 / 60 end
natives.CreateThread = function() end
natives.Wait = function() end
local origins, cleared, sprites = 0, 0, {}
local drawn = {}
natives.SetDrawOrigin = function(x) origins = origins + 1; drawn[#drawn + 1] = x end
natives.ClearDrawOrigin = function() cleared = cleared + 1 end
natives.DrawSprite = function(_, name, x, y, w, h, heading, _, _, _, a)
    sprites[#sprites + 1] = { name = name, x = x, y = y, w = w, h = h, heading = heading, alpha = a }
end

harness.load('client/eft.lua')
harness.load('client/nui.lua')
harness.load('client/accent.lua')
harness.load('client/spring.lua')
harness.load('client/render.lua')
local A, Sp, Render = EFT.Accent, EFT.Spring, EFT.Render

check('hex parses', select(2, A.parse('#f0500a')) == 80)
check('bad hex falls back to nil', A.parse('orange') == nil)
check('the export colour wins', select(3, A.rgb()) == 0x99)
exported = nil
harness.load('client/accent.lua')
check('a missing export falls back to the default', select(1, EFT.Accent.rgb()) == 0xf0)
A = EFT.Accent
handlers['ef_lib:accentChanged']('#00ff00')
check('an accent event updates the colour', select(2, A.rgb()) == 255 and sent[#sent].action == 'accent'
    and sent[#sent].hex == '#00ff00')
handlers['ef_lib:accentChanged']('nonsense')
check('a bad accent event is ignored', select(2, A.rgb()) == 255)

local s = { value = 0, velocity = 0 }
for _ = 1, 120 do Sp.step(s, 1, 1 / 60) end
check('the spring settles on its target', math.abs(s.value - 1) < 0.01)
check('a long frame does not explode', math.abs(Sp.step({ value = 0, velocity = 0 }, 1, 5.0)) < 2)

local thirty = {}
for i = 1, 30 do thirty[i] = { key = 'p' .. i, coords = vec3(i, 0, 0), distance = 31 - i } end
Render.start(); Render.setPoints(thirty)
check('start marks the renderer running', Render.isRunning())
Render.drawFrame()
check('draw origins stay below the limit', origins <= Config.MaxPoints + 1)
check('every origin is cleared', cleared == origins)

origins, cleared, drawn = 0, 0, {}
Render.setAim(thirty[30], true); Render.drawFrame()
local lowest, seen = 99, {}
for _, x in ipairs(drawn) do lowest = math.min(lowest, x); seen[x] = true end
check('the nearest points win the limit', #drawn == Config.MaxPoints and lowest == 7 and seen[30] and seen[7])
check('every origin is cleared with an aim', cleared == origins)

sprites = {}
local function frames(n) for _ = 1, n do Render.drawFrame() end end
Render.setPoints({ thirty[1] }); Render.setAim({ key = 'x', coords = vec3(0, 0, 0) }, true); frames(60)
sprites = {}; Render.drawFrame()
local first = sprites[1]
check('a point is a diamond', first.name == 'point' and math.abs(first.heading - 45.0) < 0.1)
check('the own marker is a diamond', sprites[#sprites].name:sub(1, 5) == 'frame' and math.abs(sprites[#sprites].heading - 45.0) < 0.1)
check('sprite height follows the aspect ratio', math.abs(first.h / first.w - 16 / 9) < 1e-6)

local function alpha(name, x, y) return textures[name].alpha[(y + 32) * 64 + x + 32] end
local function shade(name, x, y) return textures[name].shade[(y + 32) * 64 + x + 32] end
check('every texture is committed', committed.fill and committed.point and committed.frame0 and committed.frame5)
check('the open frame has a gap in the middle of a side', alpha('frame0', 0, -22) == 0)
check('the open frame keeps its corners', alpha('frame0', -21, -22) > 200 and shade('frame0', -21, -22) == 255)
check('the last frame is closed', alpha('frame5', 0, -22) > 200)
check('the closing steps shrink the gap', alpha('frame3', 7, -22) > 200 and alpha('frame0', 7, -22) == 0)
check('the outline stays black', shade('frame5', 0, -28) == 0 and alpha('frame5', 0, -28) > 0)
check('the centre dot is painted', alpha('frame0', 0, 0) == 255)
check('a point has no dot and no gap', alpha('point', 0, 0) == 0 and alpha('point', 0, -22) > 200)

sprites = {}
Render.setPoints({}); Render.setAim({}, false); frames(60)
sprites = {}; Render.drawFrame()
check('an aim without coords draws at the screen centre', sprites[1] and math.abs(sprites[1].x - 0.5) < 0.001 and sprites[1].y == 0.5)

Render.setPoints({}); Render.setAim(nil, false)
check('the marker turns away before the thread stops', Render.needsFrame())
frames(60)
check('nothing visible stops the thread', not Render.needsFrame())
Render.stop()
check('stop ends the renderer', not Render.isRunning())

-- A fresh module per case, its texture and thread state is local
local function fresh()
    harness.load('client/render.lua')
    return EFT.Render
end

local lines = {}
local realPrint = print
_G.print = function(text) lines[#lines + 1] = text end
local txdCalls = 0
natives.CreateRuntimeTxd = function() txdCalls = txdCalls + 1; return 1 end
local paintTexture = natives.CreateRuntimeTexture
natives.CreateRuntimeTexture = function() error('boom') end
Render = fresh()
local startOk = pcall(Render.start); pcall(Render.start)
Render.setPoints({ thirty[1] })
_G.print = realPrint
check('a throwing texture load does not raise', startOk)
check('a failed load never becomes active', not Render.isRunning() and not Render.needsFrame())
check('a failed load is not retried', txdCalls == 1)
check('a failed load reports once', #lines == 1)

lines, txdCalls = {}, 0
natives.CreateRuntimeTexture = function() return nil end
Render = fresh()
_G.print = function(text) lines[#lines + 1] = text end
startOk = pcall(Render.start); pcall(Render.start)
_G.print = realPrint
check('a falsy texture return counts as failure', startOk and not Render.isRunning() and txdCalls == 1 and #lines == 1)

natives.CreateRuntimeTxd = function() return 1 end
natives.CreateRuntimeTexture = paintTexture
Render = fresh()
Render.start(); Render.stop(); Render.setPoints({ thirty[1] }); Render.start()
check('points set while stopped are ignored', not Render.needsFrame())
Render.stop()

local function headings()
    sprites = {}
    Render.drawFrame()
    return sprites[1], sprites[#sprites]
end
Render = fresh()
Render.start(); Render.setPoints({ thirty[1] }); Render.setAim({}, false)
local point, marker = headings()
check('a marker starts as a square', marker.heading < 10.0 and point.heading < 10.0)
frames(60)
Render.setAim(nil, false); Render.stop()
point, marker = headings()
check('a release leaves the markers on screen', marker.alpha == 255 and point.alpha == 255)
check('a release turns them back', marker.heading < 45.0 and point.heading < 45.0 and Render.needsFrame())
frames(3)
local turning = select(2, headings()).heading
Render.start(); Render.setAim({}, false)
check('a new press carries on from the turn', select(2, headings()).heading > turning - 8.0)
frames(60)
Render.setAim(nil, false); Render.stop()
frames(60)
check('turned away means gone', not Render.needsFrame())

Render = fresh()
Render.start(); Render.setPoints({ thirty[1] }); frames(60)
Render.setAim({}, false)
point, marker = headings()
sprites = {}; Render.setPoints({ { key = 'o', coords = vec3(1, 0, 0), distance = 1, offScreen = true } }); Render.drawFrame()
check('a point off screen costs no sprite', #sprites == 1 and sprites[1].name ~= 'point')
Render.setAim(nil, false); frames(60); Render.setPoints({ thirty[1] }); frames(60)
Render.setAim({}, false)
point, marker = headings()
check('near points stay while the own marker turns in', math.abs(point.heading - 45.0) < 0.1 and marker.heading < 10.0)
frames(60)
Render.setAim({ key = 'p', coords = vec3(0, 0, 0) }, true)
marker = select(2, headings())
check('a new aim starts where the marker was', math.abs(marker.x + 0.2) < 0.03)
frames(60); marker = select(2, headings())
check('the marker lands on its target', math.abs(marker.x) < 0.001)
Render.setAim(nil, false); Render.stop()

-- The thread runs inline here, a Wait hook ends it after the springs settled on a hit
local waits = 0
natives.CreateThread = function(fn) fn() end
natives.Wait = function()
    waits = waits + 1
    if waits == 60 then Render.setAim(nil, false) end
end
Render = fresh()
Render.start(); Render.setAim({}, true)
check('the thread ends once nothing is visible', waits > 60 and not Render.needsFrame())
sprites = {}
natives.CreateThread = function() end
Render.setAim({}, false); Render.drawFrame()
local filled = false
for _, sp in ipairs(sprites) do if sp.name == 'fill' then filled = true end end
check('a new aim does not start from the old hit state', not filled)
Render.stop()

Config.Reticle = { Thickness = 3.5, CenterDot = false }
Render = fresh()
Render.start(); Render.stop()
check('a thick line covers what the outline had', shade('frame5', 0, -27) == 255)
check('the centre dot can be turned off', alpha('frame0', 0, 0) == 0)
Config.Reticle = { Thickness = 2.0, CenterDot = true }
Render = fresh()
Render.start(); Render.stop()
check('a thin line leaves that pixel to the outline', shade('frame5', 0, -27) == 0)

for _, name in ipairs({ 'Config', 'json', 'exports', 'SendNuiMessage', 'AddEventHandler', 'CreateRuntimeTxd',
    'CreateRuntimeTexture', 'SetRuntimeTexturePixel', 'CommitRuntimeTexture', 'GetAspectRatio', 'GetFrameTime', 'CreateThread', 'Wait', 'SetDrawOrigin',
    'ClearDrawOrigin', 'DrawSprite' }) do _G[name] = nil end
harness.resetEFT()
