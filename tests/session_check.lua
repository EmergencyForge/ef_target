local harness = require('tests.harness')
local check = harness.check
local natives = harness.natives

harness.resetEFT()
_G.Config = { DefaultDistance = 7.0, Locale = 'de' }
_G.L = function(text) return text end
_G.GetGameTimer = function() return 1000 end
_G.json = { encode = function(t) return t end }
local sent = {}
natives.SendDuiMessage = function(_, msg) sent[#sent + 1] = msg end
natives.CreateDui = function() return 1 end
natives.GetDuiHandle = function() return 'dui' end
natives.CreateRuntimeTextureFromDuiHandle = function() return 1 end
natives.GetCurrentResourceName = function() return 'ef_target' end
natives.CreateRuntimeTxd = function() return 1 end
natives.AddEventHandler = function() end
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
local places = 0
EFT.Surface = { place = function() places = places + 1 end, visible = function() end }
harness.load('client/session.lua')
local S = EFT.Session
local function confirms()
    local n = 0
    for _, message in ipairs(sent) do
        if message.action == 'confirm' then n = n + 1 end
    end
    return n
end

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
check('idle ox_lib does not block', S.blocked(true) == false and oxCalls == 1)
oxBusy = true
check('a scan keeps the last answer for a moment', S.blocked() == false and oxCalls == 1)
check('an active ox_lib progress blocks', S.blocked(true) == true)
_G.GetGameTimer = function() return 1250 end
oxBusy = false
check('the answer runs out', S.blocked() == false and oxCalls == 3)
_G.GetGameTimer = function() return 1000 end
oxBusy = 'throw'
check('a throwing ox_lib export does not block', S.blocked(true) == false)
oxBusy, oxCalls, oxState = true, 0, 'stopped'
check('a stopped ox_lib is not asked', S.blocked(true) == false and oxCalls == 0)
_G.GetResourceState, _G.exports = nil, nil

check('a session starts', S.begin() == true and S.isActive())
S.update(two)
check('the first row is selected', sent[#sent].index == 1)
check('show carries only row display fields', sent[#sent].action == 'show' and sent[#sent].rows[1].onSelect == nil
    and sent[#sent].rows[1].option == nil)
check('a new target places the surface', places == 1)
local count = #sent
S.update(two); check('nothing new means no message', #sent == count)
check('the same target keeps its place', places == 1)
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
check('a run option confirms once', confirms() == 1 and sent[#sent - 1].action == 'confirm')

S.begin()
local confirmed = confirms()
local sub = target({ { name = 'sub', label = 'Sub', openMenu = 'm' }, { name = 'in', label = 'In', menuName = 'm', onSelect = run } })
S.update(sub); S.click()
check('a submenu keeps the session open', S.isActive() and sent[#sent].action == 'show' and S.menu() == 'm')
check('opening a submenu confirms nothing', confirms() == confirmed)
S.stop('test')
S.begin(); S.update(sub)
check('stop resets the menu', S.menu() == nil and sent[#sent].rows[1].label == 'Sub')

-- The menu belongs to what it was opened on
local other = target({ { name = 'other', label = 'Other' } })
other.entity = 6
S.click()
check('the submenu is open', S.menu() == 'm')
S.update(other)
check('another entity drops the submenu', sent[#sent].action == 'show' and sent[#sent].rows[1].label == 'Other' and #sent[#sent].rows == 1)
S.update(sub)
check('the first entity starts at home again', S.menu() == nil)
S.click()
local placedBefore = places
S.update(nil); S.update(sub)
check('a target lost for a moment keeps the submenu', S.menu() == 'm')
check('a target found again is placed anew', places == placedBefore + 1)
local onPoint = target({ { name = 'general', label = 'General' } })
onPoint.point = { key = 'p1', entries = {}, distance = 1.0, entity = 5 }
S.update(onPoint)
check('another point drops the submenu', S.menu() == nil)
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
check('the next session stays at home', S.menu() == nil)
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
check('a failing old click leaves the new submenu open', S.isActive() and sent[#sent].rows and S.menu() == 'm')
S.stop('test')

-- Right click walks back the way the clicks came
local deep = target({
    { name = 'x', label = 'X', onSelect = run },
    { name = 'y', label = 'Y', openMenu = 'first' },
    { name = 'f1', label = 'F1', menuName = 'first', onSelect = run },
    { name = 'f2', label = 'F2', menuName = 'first', openMenu = 'second' },
    { name = 's1', label = 'S1', menuName = 'second', onSelect = run },
})
S.begin(); S.update(deep)
S.back()
check('back at home does nothing', sent[#sent].action == 'show' and #sent[#sent].rows == 2)
S.wheel(1); S.click()
check('a push names the direction and starts at the top', sent[#sent].nav == 'push' and S.menu() == 'first' and sent[#sent].index == 1)
S.wheel(1); S.click()
check('a second push goes one level deeper', S.menu() == 'second' and sent[#sent].rows[1].label == 'S1')
S.back()
check('back lands on the row it came from', sent[#sent].nav == 'pop' and sent[#sent].index == 2 and S.menu() == 'first')
S.back()
check('back reaches home on the row it came from', sent[#sent].index == 2 and S.menu() == nil and sent[#sent].rows[1].label == 'X')
S.click()
local emptied = target({ { name = 'x', label = 'X', onSelect = run } })
S.update(emptied)
check('an emptied submenu falls back to home', sent[#sent].rows[1].label == 'X' and S.menu() == nil)
check('the direction is used once', sent[#sent].nav == nil)
S.stop('test')

local timed = target({ { name = 't', label = 'T', hold = 1200, onSelect = run }, B })
S.begin(); S.update(timed)
check('the selected row gives its hold time', S.holdTime() == 1200 and S.selected() == sent[#sent].rows[1].id)
check('a held row carries no hint to the page', sent[#sent].rows[1].hold == nil)
S.wheel(1)
check('another row has no hold time and another id', S.holdTime() == nil and S.selected() == sent[#sent - 1].rows[2].id)
S.stop('test')
check('a stopped session has no selection', S.selected() == nil and not S.holdTime())

natives.IsPauseMenuActive = function() return true end
check('pause menu blocks a start', S.begin() == false)
natives.IsPauseMenuActive = function() return false end
S.disable(true); check('disable ends a running session', not S.isActive())
check('disable blocks a start', S.begin() == false)
S.disable(false); check('enabling allows a start again', S.begin() == true)
S.stop('done')

for _, name in ipairs({ 'Config', 'L', 'GetGameTimer', 'json', 'SendDuiMessage', 'CreateDui', 'GetDuiHandle',
    'CreateRuntimeTextureFromDuiHandle', 'GetCurrentResourceName', 'CreateRuntimeTxd', 'AddEventHandler', 'DoesEntityExist', 'IsPauseMenuActive',
    'IsNuiFocused', 'PlayerPedId', 'IsPedDeadOrDying' }) do _G[name] = nil end
harness.resetEFT()
