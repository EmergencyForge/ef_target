local harness = require('tests.harness')
local check = harness.check
local natives = harness.natives

harness.resetEFT()
_G.Config = { MaxPoints = 24 }
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
natives.CreateRuntimeTextureFromImage = function() return 1 end
natives.GetAspectRatio = function() return 16 / 9 end
natives.GetFrameTime = function() return 1 / 60 end
natives.CreateThread = function() end
natives.Wait = function() end
local origins, cleared, sprites = 0, 0, {}
local drawn = {}
natives.SetDrawOrigin = function(x) origins = origins + 1; drawn[#drawn + 1] = x end
natives.ClearDrawOrigin = function() cleared = cleared + 1 end
natives.DrawSprite = function(_, name, x, y, w, h) sprites[#sprites + 1] = { name = name, x = x, y = y, w = w, h = h } end

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
Render.setPoints({ thirty[1] }); Render.setAim({ key = 'x', coords = vec3(0, 0, 0) }, true); Render.drawFrame()
local first = sprites[1]
local haloSeen = false
for _, sp in ipairs(sprites) do if sp.name == 'halo' then haloSeen = true end end
check('a hit draws the thin halo', haloSeen)
check('sprite height follows the aspect ratio', math.abs(first.h / first.w - 16 / 9) < 1e-6)

sprites = {}
Render.setPoints({}); Render.setAim({}, false); Render.drawFrame()
check('an aim without coords draws at the screen centre', sprites[1] and sprites[1].x == 0.5 and sprites[1].y == 0.5)

Render.setPoints({}); Render.setAim(nil, false)
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
natives.CreateRuntimeTextureFromImage = function() error('boom') end
Render = fresh()
local startOk = pcall(Render.start); pcall(Render.start)
Render.setPoints({ thirty[1] })
_G.print = realPrint
check('a throwing texture load does not raise', startOk)
check('a failed load never becomes active', not Render.isRunning() and not Render.needsFrame())
check('a failed load is not retried', txdCalls == 1)
check('a failed load reports once', #lines == 1)

lines, txdCalls = {}, 0
natives.CreateRuntimeTextureFromImage = function() return nil end
Render = fresh()
_G.print = function(text) lines[#lines + 1] = text end
startOk = pcall(Render.start); pcall(Render.start)
_G.print = realPrint
check('a falsy texture return counts as failure', startOk and not Render.isRunning() and txdCalls == 1 and #lines == 1)

natives.CreateRuntimeTxd = function() return 1 end
natives.CreateRuntimeTextureFromImage = function() return 1 end
Render = fresh()
Render.start(); Render.stop(); Render.setPoints({ thirty[1] }); Render.start()
check('points set while stopped are ignored', not Render.needsFrame())
Render.stop()

-- The thread runs inline here, a Wait hook ends it after the springs settled on a hit
local waits = 0
natives.CreateThread = function(fn) fn() end
natives.Wait = function()
    waits = waits + 1
    if waits == 60 then Render.setAim(nil, false) end
end
Render = fresh()
Render.start(); Render.setAim({}, true)
check('the thread ends once nothing is visible', waits == 60 and not Render.needsFrame())
sprites = {}
natives.CreateThread = function() end
Render.setAim({}, false); Render.drawFrame()
local filled = false
for _, sp in ipairs(sprites) do if sp.name == 'fill' then filled = true end end
check('a new aim does not start from the old hit state', not filled)
Render.stop()

for _, name in ipairs({ 'Config', 'json', 'exports', 'SendNuiMessage', 'AddEventHandler', 'CreateRuntimeTxd',
    'CreateRuntimeTextureFromImage', 'GetAspectRatio', 'GetFrameTime', 'CreateThread', 'Wait', 'SetDrawOrigin',
    'ClearDrawOrigin', 'DrawSprite' }) do _G[name] = nil end
harness.resetEFT()
