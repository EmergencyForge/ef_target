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
natives.SetDrawOrigin = function() origins = origins + 1 end
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
Render.setPoints(thirty); Render.start()
check('start marks the renderer running', Render.isRunning())
Render.drawFrame()
check('draw origins stay below the limit', origins <= Config.MaxPoints + 1)
check('every origin is cleared', cleared == origins)

origins, cleared = 0, 0
Render.setAim(thirty[30], true); Render.drawFrame()
check('the nearest points win the limit', origins == Config.MaxPoints + 1 or origins == Config.MaxPoints)
check('every origin is cleared with an aim', cleared == origins)

sprites = {}
Render.setPoints({ thirty[1] }); Render.setAim({ key = 'x', coords = vec3(0, 0, 0) }, true); Render.drawFrame()
local first = sprites[1]
check('sprite height follows the aspect ratio', math.abs(first.h / first.w - 16 / 9) < 1e-6)

sprites = {}
Render.setPoints({}); Render.setAim({}, false); Render.drawFrame()
check('an aim without coords draws at the screen centre', sprites[1] and sprites[1].x == 0.5 and sprites[1].y == 0.5)

Render.setPoints({}); Render.setAim(nil, false)
check('nothing visible stops the thread', not Render.needsFrame())
Render.stop()
check('stop ends the renderer', not Render.isRunning())

for _, name in ipairs({ 'Config', 'json', 'exports', 'SendNuiMessage', 'AddEventHandler', 'CreateRuntimeTxd',
    'CreateRuntimeTextureFromImage', 'GetAspectRatio', 'GetFrameTime', 'CreateThread', 'Wait', 'SetDrawOrigin',
    'ClearDrawOrigin', 'DrawSprite' }) do _G[name] = nil end
harness.resetEFT()
