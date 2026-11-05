local harness = require('tests.harness')
local check = harness.check
local natives = harness.natives

harness.resetEFT()
_G.Config = { DefaultDistance = 7.0, Locale = 'de' }
_G.L = function(text) return text end
_G.GetGameTimer = function() return 1000 end
_G.json = { encode = function(t) return t end }
local sent = {}
natives.SendNuiMessage = function(msg) sent[#sent + 1] = msg end
natives.DoesEntityExist = function() return true end
natives.IsPauseMenuActive = function() return false end
natives.IsNuiFocused = function() return false end
natives.PlayerPedId = function() return 1 end
natives.IsPedDeadOrDying = function() return false end
harness.load('client/eft.lua')
EFT.Framework = { hasGroup = function() return true end, hasItems = function() return true end }
harness.load('client/filter.lua')
harness.load('client/menu.lua')
harness.load('client/select.lua')
harness.load('client/nui.lua')
harness.load('client/session.lua')
local S = EFT.Session

local ran = 0
local function run() ran = ran + 1 end
local function target(options)
    return { entries = { { id = 1, resource = 'r', options = options } }, zones = {}, entity = 5, entityType = 2,
        coords = vec3(0, 0, 0), distance = 1.0 }
end
local A = { name = 'a', label = 'A', onSelect = run }
local B = { name = 'b', label = 'B', onSelect = run }
local two, reversed, one = target({ A, B }), target({ B, A }), target({ A })

check('a session starts', S.begin() == true and S.isActive())
S.update(two)
check('the first row is selected', sent[#sent].index == 1)
check('show carries only row display fields', sent[#sent].action == 'show' and sent[#sent].rows[1].onSelect == nil
    and sent[#sent].rows[1].option == nil and sent[#sent].title == 'Fahrzeug')
local count = #sent
S.update(two); check('nothing new means no message', #sent == count)
S.wheel(1); S.wheel(1); check('the wheel wraps around', sent[#sent].action == 'select' and sent[#sent].index == 1)
S.wheel(1); S.update(reversed)
check('the selection follows its option', sent[#sent].index == 1)
S.update(nil); check('losing the target hides the panel', sent[#sent].action == 'hide')
count = #sent
S.update(nil); check('hiding twice sends once', #sent == count)
S.click(); check('a click with no target does nothing', ran == 0)
S.update(one); natives.DoesEntityExist = function() return false end
S.click(); check('a click on a deleted entity runs nothing', ran == 0 and sent[#sent].action == 'hide')
natives.DoesEntityExist = function() return true end
S.update(one); S.click()
check('a run option ends the session', ran == 1 and not S.isActive())

S.begin()
local sub = target({ { name = 'sub', label = 'Sub', openMenu = 'm' }, { name = 'in', label = 'In', menuName = 'm', onSelect = run } })
S.update(sub); S.click()
check('a submenu keeps the session open', S.isActive() and sent[#sent].action == 'show' and sent[#sent].rows[1].id == 'builtin:goback')
S.stop('test')
S.begin(); S.update(sub)
check('stop resets the menu', sent[#sent].rows[1].id ~= 'builtin:goback')

natives.IsPauseMenuActive = function() return true end
check('pause menu blocks a start', S.begin() == false)
natives.IsPauseMenuActive = function() return false end
S.disable(true); check('disable ends a running session', not S.isActive())
check('disable blocks a start', S.begin() == false)
S.disable(false); check('enabling allows a start again', S.begin() == true)
S.stop('done')

for _, name in ipairs({ 'Config', 'L', 'GetGameTimer', 'json', 'SendNuiMessage', 'DoesEntityExist', 'IsPauseMenuActive',
    'IsNuiFocused', 'PlayerPedId', 'IsPedDeadOrDying' }) do _G[name] = nil end
harness.resetEFT()
