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

-- ox_lib exports every lib function, the lib table itself is not in this resource
local oxState, oxBusy, oxCalls = 'started', false, 0
_G.GetResourceState = function() return oxState end
_G.exports = {
    ox_lib = { progressActive = function() oxCalls = oxCalls + 1; if oxBusy == 'throw' then error('old lib') end return oxBusy end },
    ef_lib = { IsProgressBarActive = function() return false end },
}
check('idle ox_lib does not block', S.blocked() == false and oxCalls == 1)
oxBusy = true
check('an active ox_lib progress blocks', S.blocked() == true)
oxBusy = 'throw'
check('a throwing ox_lib export does not block', S.blocked() == false)
oxBusy, oxCalls, oxState = true, 0, 'stopped'
check('a stopped ox_lib is not asked', S.blocked() == false and oxCalls == 0)
_G.GetResourceState, _G.exports = nil, nil

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

-- The menu belongs to what it was opened on
local other = target({ { name = 'other', label = 'Other' } })
other.entity = 6
S.click()
check('the submenu is open', sent[#sent].rows[1].id == 'builtin:goback')
S.update(other)
check('another entity drops the submenu', sent[#sent].action == 'show' and sent[#sent].rows[1].label == 'Other' and #sent[#sent].rows == 1)
S.update(sub)
check('the first entity starts at home again', sent[#sent].rows[1].id ~= 'builtin:goback')
S.click()
S.update(nil); S.update(sub)
check('a target lost for a moment keeps the submenu', sent[#sent].rows[1].id == 'builtin:goback')
local onPoint = target({ { name = 'general', label = 'General' } })
onPoint.point = { key = 'p1', entries = {}, distance = 1.0, entity = 5 }
S.update(onPoint)
check('another point drops the submenu', sent[#sent].rows[1].id ~= 'builtin:goback')
S.stop('test')

-- One option split over bones gives points with equal rows, a new snap still goes back to the top
local function splitPoint(key)
    local t = target({ { name = 'general', label = 'General' } })
    local e = { id = 2, resource = 'r', options = { { name = 'split', label = 'Split' } }, anchor = { bone = key } }
    t.point = { key = key, entries = { e }, distance = 1.0, entity = 5, label = 'Rad' }
    return t
end
S.begin()
S.update(splitPoint('wheel_lf'))
S.wheel(1)
check('the wheel leaves the first row', sent[#sent].index == 2)
S.update(splitPoint('wheel_rf'))
check('a new snap with equal rows selects the first row', sent[#sent].action == 'select' and sent[#sent].index == 1)
S.stop('test')

-- A click can outlive its session when the option blocks
local function ranAcross(option)
    S.begin()
    S.update(target({ option, B }))
    local handle = option.onSelect
    option.onSelect = function(data)
        S.stop('tapped')
        S.begin()
        S.update(two)
        handle(data)
    end
    S.click()
    option.onSelect = handle
end
local before = ran
ranAcross({ name = 'c', label = 'C', onSelect = run })
check('a closed result leaves the next session alone', S.isActive() and ran == before + 1)
count = #sent
S.wheel(1)
check('the next session keeps its rows', sent[#sent].action == 'select' and #sent == count + 1)
S.stop('test')
ranAcross({ name = 'm', label = 'M', openMenu = 'm2', onSelect = run })
count = #sent
S.wheel(1)
check('a menu result leaves the next session alone', S.isActive() and sent[#sent].action == 'select' and #sent == count + 1)
S.update(two)
check('the next session stays at home', sent[#sent].action == 'select' or sent[#sent].rows[1].id ~= 'builtin:goback')
S.stop('test')

-- A failing option rolls its menu change back, that must not reach the session after it
local realPrint = print
_G.print = function() end
ranAcross({ name = 'e', label = 'E', openMenu = 'm3', onSelect = function()
    S.update(sub)
    S.click()
    error('boom')
end })
_G.print = realPrint
S.update(sub)
check('a failing old click leaves the new submenu open', S.isActive() and sent[#sent].rows and sent[#sent].rows[1].id == 'builtin:goback')
S.stop('test')

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
