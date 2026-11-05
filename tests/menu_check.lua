local harness = require('tests.harness')
local check = harness.check

harness.resetEFT()
_G.Config = { DefaultDistance = 7.0, Locale = 'de' }
_G.L = function(text) return text end
_G.GetGameTimer = function() return 1000 end
_G.DoesEntityExist = function(entity) return entity ~= 99 end
harness.load('client/eft.lua')
EFT.Framework = { hasGroup = function() return true end, hasItems = function() return true end }
harness.load('client/filter.lua')
harness.load('client/menu.lua')
harness.load('client/select.lua')
local M, S = EFT.Menu, EFT.Select

local function entry(options, extra)
    local e = { id = 1, resource = 'res_m', options = options, show = 'alt' }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

local point = { key = 'k', coords = vec3(1, 1, 1), label = 'Tür', distance = 1.0, entity = 5,
    entries = { entry({ { label = 'Tür öffnen' }, { label = 'Tür schließen', distance = 0.5 } }, { id = 2, anchor = { bone = 'door' } }) } }
local general = entry({ { label = 'Durchsuchen' } }, { id = 3 })
local zone = { id = 4, label = 'Zone', resource = 'res_z', options = { { label = 'Betreten' } } }
local state = { history = {} }
local onPoint = { point = point, entries = { general }, zones = { zone }, entity = 5, entityType = 2, coords = vec3(0, 0, 0), distance = 2.0 }
local noPoint = { entries = { general }, zones = {}, entity = 5, entityType = 2, coords = vec3(0, 0, 0), distance = 2.0 }

local rows, title = M.build(onPoint, state)
check('point options come first', rows[1].label == 'Tür öffnen')
check('a point option out of range is dropped', #rows == 3)
check('general options follow behind a divider', rows[2].label == 'Durchsuchen' and rows[2].divider and not rows[1].divider)
check('zone rows come last with their own id', rows[3].id == 'z4:1' and rows[3].entry == zone and rows[1].id == '2:1')
check('the title is the point label', title == 'Tür')
check('without a point there is no divider', not M.build(noPoint, state)[1].divider)
check('the title falls back to the entity type', select(2, M.build(noPoint, state)) == 'Fahrzeug')
check('a zone only target is titled by the zone', select(2, M.build({ entries = {}, zones = { zone }, entity = 0, entityType = 0, coords = vec3(0, 0, 0), distance = 1 }, state)) == 'Zone')

local inSub = { entries = { entry({ { label = 'Sub', menuName = 'sub' }, { label = 'Home' } }) }, zones = {}, entity = 5, entityType = 1, coords = vec3(0, 0, 0), distance = 1 }
local subRows = M.build(inSub, { menu = 'sub', history = {} })
check('a submenu offers the way back', subRows[1].option.name == 'builtin:goback' and subRows[2].label == 'Sub' and #subRows == 2)
check('the home menu hides submenu options', #M.build(inSub, state) == 1)

check('signature ignores callbacks', M.signature(rows) == M.signature(M.build(onPoint, state)))
local cbTarget = { entries = { entry({ { label = 'A', onSelect = function() end } }) }, zones = {}, entity = 5, entityType = 1, coords = vec3(0, 0, 0), distance = 1 }
local other = { entries = { entry({ { label = 'A', onSelect = print } }) }, zones = {}, entity = 5, entityType = 1, coords = vec3(0, 0, 0), distance = 1 }
check('signature is equal for different callbacks', M.signature(M.build(cbTarget, state)) == M.signature(M.build(other, state)))
check('signature changes with the label', M.signature(rows) ~= M.signature(M.build(noPoint, state)))

local unlimited = entry({ { label = 'Anywhere' } }, { id = 9, unlimited = true })
check('unlimited entries ignore the distance', #M.build({ entries = { unlimited }, zones = {}, entity = 5, entityType = 1, coords = vec3(0, 0, 0), distance = 50 }, state) == 1)

local target = { entity = 5, coords = vec3(0, 0, 0), distance = 1.0, netId = 77 }
local ran = false
local row = { option = { canInteract = function() return false end, onSelect = function() ran = true end } }
check('a stale option does not run', S.run(row, target, state) == 'stale' and not ran)
check('a vanished entity is stale', S.run({ option = { onSelect = function() ran = true end } }, { entity = 99 }, state) == 'stale' and not ran)

local warned
local realPrint = print
_G.print = function(text) warned = text end
row = { option = { name = 'boomer', onSelect = function() error('boom') end } }
local outcome = S.run(row, target, state)
_G.print = realPrint
check('a throwing onSelect closes cleanly', outcome == 'closed')
check('the warning names the option', warned ~= nil and warned:find('boomer', 1, true) ~= nil)

row = { option = { qtarget = true, onSelect = function(a) ran = a end } }
S.run(row, { entity = 7 }, state); check('qtarget gets the entity itself', ran == 7)
row = { option = { onSelect = function(a) ran = a end, label = 'R' } }
S.run(row, target, state); check('onSelect gets the response', ran.entity == 5 and ran.label == 'R')

local exported
_G.exports = setmetatable({}, { __index = function(_, res) return { fn = function(_, data) exported = { res, data } end } end })
S.run({ option = { export = 'fn', label = 'E' }, entry = { resource = 'res_e' } }, target, state)
check('export falls back to the entry resource', exported and exported[1] == 'res_e' and exported[2].label == 'E')
S.run({ option = { export = 'fn', resource = 'res_o' }, entry = { resource = 'res_e' } }, target, state)
check('the option resource wins', exported[1] == 'res_o')

local sent
_G.TriggerEvent = function(name, data) sent = { 'ev', name, data } end
_G.TriggerServerEvent = function(name, data) sent = { 'sv', name, data } end
_G.ExecuteCommand = function(cmd) sent = { 'cmd', cmd } end
S.run({ option = { event = 'a:b' } }, target, state); check('event is triggered', sent[1] == 'ev' and sent[2] == 'a:b')
S.run({ option = { serverEvent = 'a:c' } }, target, state); check('serverEvent carries the netId', sent[1] == 'sv' and sent[3].entity == 77)
S.run({ option = { command = 'say hi' } }, target, state); check('command is executed', sent[1] == 'cmd' and sent[2] == 'say hi')

local menuState = { menu = nil, history = {} }
local opened = false
check('openMenu enters the menu and runs its target',
    S.run({ option = { openMenu = 'sub', onSelect = function() opened = true end } }, target, menuState) == 'menu'
    and menuState.menu == 'sub' and opened)
check('the way back pops the history', S.run({ option = { name = 'builtin:goback' } }, target, menuState) == 'menu' and menuState.menu == nil)
S.run({ option = { openMenu = 'a' } }, target, menuState)
S.run({ option = { openMenu = 'b' } }, target, menuState)
S.run({ option = { name = 'builtin:goback' } }, target, menuState)
check('back goes one level up', menuState.menu == 'a')
S.run({ option = { openMenu = 'home' } }, target, menuState)
check('home means no menu', menuState.menu == nil)

local netTarget = { entity = 5, netId = 77, coords = vec3(0, 0, 0), distance = 1 }
check('the server response carries the netId', S.response({}, netTarget, true).entity == 77)
check('the server response without a netId carries 0', S.response({}, { entity = 5 }, true).entity == 0)
local r = S.response({ onSelect = print, icon = 'x', groups = 'g', label = 'K' }, target)
check('the response drops internals', r.icon == nil and r.onSelect == nil and r.groups == nil and r.label == 'K')
check('the response carries zone and point', S.response({}, target, false, { zone = 4 }).zone == 4
    and S.response({}, target, false, { point = point }).point.key == 'k')
check('the response does not touch the option', (function() local o = { icon = 'x' }; S.response(o, target); return o.icon == 'x' end)())

-- Leave no stubs behind for the checks that run after this file
for _, name in ipairs({ 'Config', 'L', 'GetGameTimer', 'DoesEntityExist', 'exports', 'TriggerEvent', 'TriggerServerEvent', 'ExecuteCommand' }) do
    _G[name] = nil
end
harness.resetEFT()
