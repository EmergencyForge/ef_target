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
EFT.Nui = { confirm = function() end }
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

local rows = M.build(onPoint, state)
check('point options come first', rows[1].label == 'Tür öffnen')
check('a point option out of range is dropped', #rows == 3)
check('general options follow behind a divider', rows[2].label == 'Durchsuchen' and rows[2].divider and not rows[1].divider)
check('zone rows come last with their own id', rows[3].id == 'z4:1' and rows[3].entry == zone and rows[1].id == '2:1')
check('without a point there is no divider', not M.build(noPoint, state)[1].divider)
check('the menu has no heading any more', select('#', M.build(noPoint, state)) == 1)

local inSub = { entries = { entry({ { label = 'Sub', menuName = 'sub' }, { label = 'Home' } }) }, zones = {}, entity = 5, entityType = 1, coords = vec3(0, 0, 0), distance = 1 }
local subRows = M.build(inSub, { menu = 'sub', history = {} })
check('a submenu shows its own rows only', subRows[1].label == 'Sub' and #subRows == 1)
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

local internals = S.response({ label = 'x', guard = print, qbInteract = true }, { entity = 7 }, false)
check('compat internals stay out of the response', internals.guard == nil and internals.qbInteract == nil)

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

-- Point rows use the point's own context, both when shown and when run
local seen
local ptPoint = { key = 'p', coords = vec3(9, 9, 9), distance = 1.0, entity = 6,
    entries = { entry({ { label = 'Near', canInteract = function(_, d) return d == 1.0 end, onSelect = function(r) seen = r end } }, { id = 7, anchor = { bone = 'b' } }) } }
local ptTarget = { point = ptPoint, entries = {}, zones = {}, entity = 5, entityType = 2, coords = vec3(0, 0, 0), distance = 4.0 }
local ptRows = M.build(ptTarget, state)
check('a point option is judged by the point distance', #ptRows == 1)
check('a point option still runs on click', S.run(ptRows[1], ptTarget, state) == 'closed' and seen ~= nil)
check('its response carries the point coords and distance', seen.coords == vec3(9, 9, 9) and seen.distance == 1.0)

local hidden = { point = { key = 'h', coords = vec3(1, 1, 1), distance = 1.0, entity = 5,
    entries = { entry({ { label = 'Hidden', canInteract = function() return false end } }, { id = 8, anchor = { bone = 'b' } }) } },
    entries = { general }, zones = {}, entity = 5, entityType = 2, coords = vec3(0, 0, 0), distance = 2.0 }
check('no divider when every point option is filtered out', not M.build(hidden, state)[1].divider)

local timed = { entries = { entry({ { label = 'Lang', hold = 1500 }, { label = 'Null', hold = 0 }, { label = 'Text', hold = 'x' }, { label = 'Tief', openMenu = 'm' } }) },
    zones = {}, entity = 5, entityType = 2, coords = vec3(0, 0, 0), distance = 1.0 }
local timedRows = M.build(timed, state)
check('hold reaches the row', timedRows[1].hold == 1500)
check('a hold that is no positive number runs on the press', timedRows[2].hold == nil and timedRows[3].hold == nil)
check('a row knows it opens a submenu', timedRows[4].submenu == true and not timedRows[1].submenu)
timed.entries[1].options[1].hold = 900
check('the signature sees a new hold', M.signature(M.build(timed, state)) ~= M.signature(timedRows))

local failState = { menu = 'a', history = { 'home' } }
_G.print = function() end
local failed = S.run({ option = { openMenu = 'b', onSelect = function() error('x') end } }, target, failState)
_G.print = realPrint
check('a throwing target after openMenu restores the menu', failed == 'closed' and failState.menu == 'a' and #failState.history == 1)

-- The entity a point row acts on is the point's, not the target's
_G.NetworkGetEntityIsNetworked = function(e) return e == 6 end
_G.NetworkGetNetworkIdFromEntity = function(e) return e * 100 end
local ptNet = { point = ptPoint, netId = 55, entity = 5, coords = vec3(0, 0, 0), distance = 4.0 }
local ptRow = { point = ptPoint, option = {} }
check('a point response carries the point entity', seen.entity == 6)
check('a point server response resolves the point net id', S.response({}, ptNet, true, ptRow).entity == 600)
check('a point on the target entity keeps target.netId', S.response({}, ptNet, true, { point = { entity = 5 } }).entity == 55)
check('an unnetworked point entity gives 0', S.response({}, ptNet, true, { point = { entity = 7 } }).entity == 0)
local coordsRow = { point = { key = 'c', coords = vec3(1, 1, 1) }, option = {} }
check('a coords point gives nil client and 0 server', S.response({}, ptNet, false, coordsRow).entity == nil and S.response({}, ptNet, true, coordsRow).entity == 0)
S.run({ point = ptPoint, option = { qtarget = true, onSelect = function(a) seen = a end } }, ptTarget, state)
check('qtarget on a point row gets the point entity', seen == 6)
_G.NetworkGetEntityIsNetworked, _G.NetworkGetNetworkIdFromEntity = nil, nil

-- A coords point has no entity: neither the callback nor the stale check may fall back to the target's
local called, arg = false, 'unset'
local coordsPoint = { key = 'cp', coords = vec3(2, 2, 2), distance = 1.0 }
S.run({ point = coordsPoint, option = { qtarget = true, onSelect = function(a) called, arg = true, a end } }, { entity = 5, coords = vec3(0, 0, 0), distance = 1 }, state)
check('qtarget on a coords point is called with nil', called and arg == nil)
called = false
check('a coords point survives a vanished target entity',
    S.run({ point = coordsPoint, option = { onSelect = function() called = true end } }, { entity = 99, coords = vec3(0, 0, 0), distance = 1 }, state) == 'closed' and called)

-- Leave no stubs behind for the checks that run after this file
for _, name in ipairs({ 'Config', 'L', 'GetGameTimer', 'DoesEntityExist', 'exports', 'TriggerEvent', 'TriggerServerEvent', 'ExecuteCommand' }) do
    _G[name] = nil
end
harness.resetEFT()
