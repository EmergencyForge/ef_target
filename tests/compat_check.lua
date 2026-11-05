local harness = require('tests.harness')
local check = harness.check
local natives = harness.natives

harness.resetEFT()

local invoking = 'res_caller'
local reported = {}
-- handle to netId of the networked entities in this test
local networked = { [1055] = 55, [1056] = 56 }
local handleOf = { [55] = 1055, [56] = 1056 }

natives.GetInvokingResource = function() return invoking end
natives.GetCurrentResourceName = function() return 'ef_target' end
natives.joaat = function(name)
    local hash = 7
    for i = 1, #name do hash = hash * 31 + name:byte(i) end
    return hash
end
natives.GetNumResources = function() return 1 end
natives.GetResourceByFindIndex = function() return 'ef_target' end
natives.NetworkGetEntityIsNetworked = function(entity) return networked[entity] ~= nil end
natives.NetworkGetNetworkIdFromEntity = function(entity) return networked[entity] end
natives.NetworkDoesNetworkIdExist = function(netId) return handleOf[netId] ~= nil end
natives.NetworkGetEntityFromNetworkId = function(netId) return handleOf[netId] end
natives.DoesEntityExist = function(entity) return entity ~= 404 end
natives.IsPedAPlayer = function(entity) return entity == 900 end
natives.TriggerServerEvent = function(name, netId) reported[#reported + 1] = name .. ':' .. tostring(netId) end
natives.SetTimeout = function() end

local events, efExports = {}, {}
local function loadCompat()
    _G.AddEventHandler = function(name, fn) events[name] = fn end
    harness.load('client/compat/ox.lua')
    harness.load('client/compat/qb.lua')
    _G.AddEventHandler = nil
end

harness.load('client/eft.lua')
harness.load('client/geometry.lua')
harness.load('client/registry.lua')
loadCompat()
local R = EFT.Registry

local sessionDisabled, sessionActive
EFT.Session = {
    disable = function(state) sessionDisabled = state end,
    isActive = function() return sessionActive end,
}
local current
EFT.Scan = { current = function() return current end }

_G.exports = function(name, fn) efExports[name] = fn end
harness.load('client/exports.lua')
_G.exports = nil

local ox = EFT.Compat.exportsFor('ox_target')
local qb = EFT.Compat.exportsFor('qb-target')
local qtarget = EFT.Compat.exportsFor('qtarget')
local convert = EFT.Compat.convert

local function entriesFor(entityType) return R.forEntity(1000, entityType, 0, nil, false) end
local function hasNet(netId) return #R.forEntity(1000, 3, 0, netId, false) > 0 end
local function hasLocal(handle) return #R.forEntity(handle, 3, 0, nil, false) > 0 end
local function optionsForModel(name) return R.optionsOf('model', joaat(name)) end
local function optionsForLocal(handle) return R.optionsOf('local', handle) end

local function countPrints(fn)
    local saved, count = print, 0
    _G.print = function() count = count + 1 end
    fn()
    _G.print = saved
    return count
end

-- ox: the brief
ox.addGlobalVehicle({ { name = 'a', label = 'A', bones = 'boot' } })
check('ox bones become points', entriesFor(2)[1].anchor.bone == 'boot')
ox.addEntity({ 55 }, { label = 'N' })
check('ox addEntity takes netIds', hasNet(55))
check('ox addEntity reports the entity to the server', reported[1] == 'ef_target:trackEntity:55')
ox.addLocalEntity(77, { label = 'L' })
check('ox local entity is keyed by handle', hasLocal(77))
local id = ox.addSphereZone({ coords = vec3(0, 0, 0), radius = 2.0, options = { label = 'Z' } })
check('ox zone answers zoneExists', ox.zoneExists(id))
local warnings = countPrints(function() ox.removeZone('missing', true) end)
check('removing a missing zone is quiet', warnings == 0)
check('removing a missing zone warns without the flag', countPrints(function() ox.removeZone('missing') end) == 1)
ox.removeGlobalVehicle('a')
check('ox removes by name', #entriesFor(2) == 0)

-- ox: the rest of the surface
ox.addEntity(66, { label = 'gone' })
check('unknown netIds are dropped', not hasNet(66))
ox.addLocalEntity(404, { label = 'gone' })
check('missing local entities are dropped', not hasLocal(404))
ox.removeEntity(55)
check('ox removeEntity without names clears the netId', not hasNet(55))
ox.removeLocalEntity({ 77 })
check('ox removeLocalEntity without names clears the handle', not hasLocal(77))

ox.removeZone(id)
check('ox removeZone removes', not ox.zoneExists(id))
local boxId = ox.addBoxZone({ name = 'box', coords = { x = 1, y = 2, z = 3, w = 90 }, options = { label = 'B' } })
check('ox box zones default to two metres', R.zones[boxId].size.x == 2.0)
check('foreign coords become a vector', R.zones[boxId].center.x == 1 and getmetatable(R.zones[boxId].center) == getmetatable(vec3(0, 0, 0)))
check('zones answer by name', ox.zoneExists('box'))
ox.removeZone('box')
local sphereId = ox.addSphereZone({ coords = vec3(0, 0, 0), options = { label = 'S' } })
check('ox spheres default to two metres', R.zones[sphereId].radius == 2.0)
ox.removeZone(sphereId)
local polyId = ox.addPolyZone({ points = { vec3(0, 0, 0), vec3(1, 0, 0), vec3(0, 1, 0) }, thickness = 2.0, options = { label = 'P' } })
check('ox poly zones keep their shape', R.zones[polyId].kind == 'poly' and R.zones[polyId].thickness == 2.0)
ox.removeZone(polyId)

ox.addGlobalPed({ name = 'p', label = 'P' })
ox.addGlobalObject({ name = 'o', label = 'O' })
ox.addGlobalPlayer({ name = 'pl', label = 'PL' })
ox.addGlobalOption({ name = 'g', label = 'G' })
check('ox globals land on their type', R.optionsOf('global', 'ped')[1].name == 'p'
    and R.optionsOf('global', 'object')[1].name == 'o' and R.optionsOf('global', 'player')[1].name == 'pl'
    and R.optionsOf('global', 'any')[1].name == 'g')
check('ox addGlobalOption has no distance limit', R.forEntity(1000, 3, 0, nil, false)[2].unlimited == true)
ox.removeGlobalPed('p')
ox.removeGlobalObject('o')
ox.removeGlobalPlayer('pl')
ox.removeGlobalOption('g')
check('ox globals remove by name', not R.optionsOf('global', 'ped') and not R.optionsOf('global', 'object')
    and not R.optionsOf('global', 'player') and not R.optionsOf('global', 'any'))

ox.addModel('prop_a', { name = 'one', label = 'One' })
ox.addModel({ 'prop_a', 123 }, { name = 'two', label = 'Two' })
check('ox models hash names and take numbers', #optionsForModel('prop_a') == 2 and R.optionsOf('model', 123)[1].name == 'two')
ox.removeModel('prop_a', 'one')
check('ox removeModel with names keeps the rest', #optionsForModel('prop_a') == 1)
invoking = 'res_other'
ox.removeModel(123, 'two')
check('names only reach the options of the caller', #R.optionsOf('model', 123) == 1)
ox.removeModel(123)
invoking = 'res_caller'
check('ox removeModel without names clears the model', not R.optionsOf('model', 123))
ox.removeModel('prop_a')

ox.disableTargeting(true)
check('ox disableTargeting reaches the session', sessionDisabled == true)
sessionActive = true
check('ox isActive reads the session', ox.isActive() == true)

-- getTargetOptions
ox.addGlobalVehicle({ name = 'v', label = 'V', bones = { 'wheel_lf', 'wheel_rf' } })
ox.addModel(321, { label = 'M' })
ox.addEntity(56, { label = 'E' })
ox.addLocalEntity(1056, { label = 'Loc' })
ox.addGlobalOption({ name = 'any', label = 'Any' })
ox.addGlobalPlayer({ name = 'pl', label = 'PL' })
local found = ox.getTargetOptions(1056, 2, 321)
check('getTargetOptions splits by kind', #found.global == 1 and found.model[1].label == 'M'
    and found.entity[1].label == 'E' and found.localEntity[1].label == 'Loc')
check('a player only has the player list', ox.getTargetOptions(900, 1, 0).global[1].name == 'pl'
    and ox.getTargetOptions(900, 1, 0).model == nil)
current = nil
found = ox.getTargetOptions()
check('without a target only the general options answer', found.__global[1].name == 'any' and found.globalTarget == nil)
current = { entity = 1056, entityType = 2, model = 321 }
found = ox.getTargetOptions()
check('without arguments it describes the current target', found.globalTarget[1].name == 'v'
    and found.model[1].label == 'M' and found.__global[1].name == 'any')
current = nil
ox.removeGlobalVehicle('v')
ox.removeGlobalOption('any')
ox.removeGlobalPlayer('pl')
ox.removeModel(321)
ox.removeEntity(56)
ox.removeLocalEntity(1056)

-- qb and qtarget
qb.AddTargetModel({ 'prop' }, { options = { { label = 'Q', action = print, job = 'police', item = 'key' } }, distance = 3.0 })
local o = optionsForModel('prop')[1]
check('qb fields translate', o.onSelect == print and o.groups == 'police' and o.items == 'key' and o.distance == 3.0 and o.qtarget)
check('qb leaves no raw fields behind', o.action == nil and o.job == nil and o.item == nil and o.name == 'Q')
qb.RemoveTargetModel('prop', 'Q')
check('qb removes by label', not optionsForModel('prop'))

qb.AddTargetEntity(1, { options = { { label = 'S', event = 'e', type = 'server' } } })
check('qb server events translate', optionsForLocal(1)[1].serverEvent == 'e' and optionsForLocal(1)[1].event == nil)
qb.AddTargetEntity({ 1055 }, { options = { { label = 'C', event = 'cmd', type = 'command' } } })
check('qb commands translate on networked entities', R.optionsOf('entity', 55)[1].command == 'cmd')
qb.AddTargetEntity(2, { options = { { label = 'K', event = 'k', type = 'client' } } })
check('qb client events stay events', optionsForLocal(2)[1].event == 'k')
qb.RemoveTargetEntity({ 1, 1055, 2 })
check('qb removes entities of both kinds', not optionsForLocal(1) and not R.optionsOf('entity', 55) and not optionsForLocal(2))

check('hash options are folded in', #convert({ options = { x = { label = 'X' } } }) == 1)
check('required_item counts as item', convert({ options = { { label = 'R', required_item = 'bag' } } })[1].items == 'bag')
local given = { label = 'keep', action = print }
convert({ options = { given } })
check('convert leaves the given option alone', given.action == print and given.onSelect == nil)
check('an option keeps its own distance', convert({ distance = 1.0, options = { { label = 'D', distance = 5.0 } } })[1].distance == 5.0)

qb.AddGlobalPed({ options = { { label = 'P' } } })
check('qb global names exist', #entriesFor(1) == 1)
qb.RemoveGlobalPed('P')
check('qb global names remove', #entriesFor(1) == 0)
for _, kind in ipairs({ 'Ped', 'Vehicle', 'Object', 'Player' }) do
    qtarget[kind]({ options = { { label = kind } } })
    local key = kind:lower()
    local added = R.optionsOf('global', key) and R.optionsOf('global', key)[1].label == kind
    qtarget['Remove' .. kind](kind)
    check('qtarget ' .. kind .. ' adds and removes', added and not R.optionsOf('global', key))
end

qb.AddTargetBone({ 'seat_dside_f' }, { options = { { label = 'Bone' } }, distance = 2.0 })
check('qb bones become vehicle points', entriesFor(2)[1].anchor.bone == 'seat_dside_f' and entriesFor(2)[1].options[1].qtarget)
ox.removeGlobalVehicle('Bone')

local zoneId = qb.AddBoxZone('b', vec3(1, 2, 30), 4.0, 2.0, { minZ = 29.0, maxZ = 33.0, heading = 90.0 }, { options = { { label = 'B' } } })
local zone = R.zones[zoneId]
check('qb box zones span minZ to maxZ', zone.center.z == 31.0 and zone.size.z == 4.0)
check('qb box length runs along y', zone.size.x == 2.0 and zone.size.y == 4.0 and zone.rotation == 90.0)
check('qb zone options are converted', zone.options[1].qtarget and zone.name == 'b')
qb.RemoveZone('b')
check('qb RemoveZone removes by name', not R.zones[zoneId])
zone = R.zones[qb.AddBoxZone('open', vec3(0, 0, 1000), 2.0, 2.0, {}, { options = { { label = 'B' } } })]
check('a box without bounds stays around its centre', zone.center.z == 1000.0 and zone.size.z >= 100.0)
qb.RemoveZone('open')
zone = R.zones[qb.AddPolyZone('poly', { vec3(0, 0, 5), vec3(4, 0, 5), vec3(0, 4, 5) }, { minZ = 10.0, maxZ = 14.0 }, { options = { { label = 'P' } } })]
check('qb poly zones span minZ to maxZ', zone.thickness == 4.0 and zone.points[1].z == 12.0 and zone.center.z == 12.0)
qb.RemoveZone('poly')
zone = R.zones[qb.AddCircleZone('circle', vec3(0, 0, 0), 3.0, {}, { options = { { label = 'C' } } })]
check('qb circle zones are spheres', zone.kind == 'sphere' and zone.radius == 3.0)
qb.RemoveZone('circle')
qb.AddEntityZone('ez', 3, { name = 'ez' }, { options = { { label = 'EZ' } } })
check('qb entity zones sit on the entity', optionsForLocal(3)[1].label == 'EZ')
qb.RemoveZone('ez')
check('qb RemoveZone clears entity zones', not optionsForLocal(3))

for _, name in ipairs({ 'AddBoxZone', 'AddPolyZone', 'AddCircleZone', 'RemoveZone', 'AddTargetBone', 'AddTargetEntity',
    'RemoveTargetEntity', 'AddTargetModel', 'RemoveTargetModel', 'Ped', 'Vehicle', 'Object', 'Player', 'RemovePed',
    'RemoveVehicle', 'RemoveObject', 'RemovePlayer', 'AddGlobalPed', 'AddGlobalVehicle', 'AddGlobalObject',
    'AddGlobalPlayer', 'AddEntityZone' }) do
    check('qb-target and qtarget export ' .. name, type(qb[name]) == 'function' and qtarget[name] == qb[name])
end
for _, name in ipairs({ 'addPolyZone', 'addBoxZone', 'addSphereZone', 'zoneExists', 'removeZone', 'addGlobalPed',
    'removeGlobalPed', 'addGlobalVehicle', 'removeGlobalVehicle', 'addGlobalObject', 'removeGlobalObject', 'addGlobalPlayer',
    'removeGlobalPlayer', 'addModel', 'removeModel', 'addEntity', 'removeEntity', 'addLocalEntity', 'removeLocalEntity',
    'addGlobalOption', 'removeGlobalOption', 'getTargetOptions', 'disableTargeting', 'isActive' }) do
    check('ox export ' .. name, type(ox[name]) == 'function')
end

-- The export events
local answered
events['__cfx_export_qb-target_AddTargetModel'](function(fn) answered = fn end)
check('the qb export event answers with the handler', answered == qb.AddTargetModel)
events['__cfx_export_ox_target_addModel'](function(fn) answered = fn end)
check('the ox export event answers with the handler', answered == ox.addModel)
events['__cfx_export_qtarget_Ped'](function(fn) answered = fn end)
check('the qtarget export event answers with the handler', answered == qtarget.Ped)

-- Options belong to the resource that called, whichever layer it came through
invoking = 'res_stopping'
local function ownedByCaller(entry) return entry and entry.resource == 'res_stopping' end
qb.AddTargetBone('bonnet', { options = { { label = 'Bone' } } })
check('a bone export belongs to the caller', ownedByCaller(entriesFor(2)[1]))
qb.AddGlobalPed({ options = { { label = 'Ped' } } })
check('a qb global belongs to the caller', ownedByCaller(entriesFor(1)[1]))
qb.AddTargetModel(321, { options = { { label = 'Model' } } })
check('a qb model belongs to the caller', ownedByCaller(R.forEntity(1000, 3, 321, nil, false)[1]))
qb.AddTargetEntity(4, { options = { { label = 'Entity' } } })
check('a qb entity belongs to the caller', ownedByCaller(R.forEntity(4, 3, 0, nil, false)[1]))
qb.AddEntityZone('ez', 5, {}, { options = { { label = 'EZ' } } })
check('an entity zone belongs to the caller', ownedByCaller(R.forEntity(5, 3, 0, nil, false)[1]))
ox.addEntity(55, { label = 'Net' })
check('an ox entity belongs to the caller', ownedByCaller(R.forEntity(1000, 3, 0, 55, false)[1]))
zoneId = qb.AddBoxZone('owned', vec3(0, 0, 0), 2.0, 2.0, {}, { options = { { label = 'B' } } })
check('a qb zone belongs to the caller', R.zones[zoneId].resource == 'res_stopping')
local efId = efExports.AddGlobal('object', { label = 'Object' })
check('an own export belongs to the caller', ownedByCaller(entriesFor(3)[1]) and efId ~= nil)
R.removeResource('res_stopping')
check('a stopped resource takes everything along', #entriesFor(1) == 0 and #entriesFor(2) == 0 and #entriesFor(3) == 0
    and not hasNet(55) and not hasLocal(4) and not hasLocal(5) and not R.zones[zoneId])
invoking = nil
ox.addGlobalPed({ label = 'Self' })
check('a call without an invoker counts as ef_target', entriesFor(1)[1].resource == 'ef_target')
R.removeResource('ef_target')
invoking = 'res_caller'

-- Own exports
for _, name in ipairs({ 'AddPoint', 'AddGlobal', 'AddModel', 'AddEntity', 'AddBoxZone', 'AddSphereZone', 'AddPolyZone',
    'Remove', 'DisableTargeting', 'IsActive' }) do
    check('export ' .. name, type(efExports[name]) == 'function')
end

local option = { label = 'Door' }
local pointId = efExports.AddPoint({ global = 'vehicle', bone = 'door', show = 'near', distance = 2.0, label = 'Tuer', options = { option } })
local entry = entriesFor(2)[1]
check('a global point is an anchored entry', entry.anchor.bone == 'door' and entry.show == 'near' and entry.label == 'Tuer')
check('the point distance reaches its options', entry.options[1].distance == 2.0)
efExports.Remove(pointId)
check('Remove takes a point away', #entriesFor(2) == 0)

pointId = efExports.AddPoint({ model = 'prop_atm', offset = vec3(0.0, 1.2, 0.5), options = { label = 'ATM', distance = 5.0 } })
entry = R.forEntity(1000, 3, joaat('prop_atm'), nil, false)[1]
check('a model point takes its offset in metres', entry.anchor.offset.y == 1.2 and not entry.anchor.relative)
check('an option keeps its own reach', entry.options[1].distance == 5.0)
check('show defaults to alt', entry.show == 'alt')
efExports.Remove(pointId)

pointId = efExports.AddPoint({ entity = 1055, bone = 'door', options = { label = 'Net' } })
check('a networked entity point is keyed by netId', R.forEntity(1000, 3, 0, 55, false)[1].anchor.bone == 'door')
efExports.Remove(pointId)
pointId = efExports.AddPoint({ entity = 6, bone = 'door', options = { label = 'Local' } })
check('a local entity point is keyed by handle', R.forEntity(6, 3, 0, nil, false)[1].anchor.bone == 'door')
efExports.Remove(pointId)
pointId = efExports.AddPoint({ coords = vec3(1, 2, 3), options = { label = 'Here' } })
check('a coords point is a point entry', R.coordsEntries()[1].anchor.coords.z == 3)
efExports.Remove(pointId)
check('Remove takes a coords point away', #R.coordsEntries() == 0)
check('a point needs a place', not pcall(efExports.AddPoint, { bone = 'door', options = { label = 'x' } }))
check('a point on an entity needs an anchor', not pcall(efExports.AddPoint, { global = 'vehicle', options = { label = 'x' } }))

local modelId = efExports.AddModel({ 'one', 'two' }, { label = 'Both' })
check('AddModel covers every model', #optionsForModel('one') == 1 and #optionsForModel('two') == 1)
efExports.Remove(modelId)
check('one id removes every model', not optionsForModel('one') and not optionsForModel('two'))

local entityId = efExports.AddEntity(1055, { label = 'Net' })
check('AddEntity detects networked entities', #R.optionsOf('entity', 55) == 1)
efExports.Remove(entityId)
entityId = efExports.AddEntity(7, { label = 'Local' })
check('AddEntity detects local entities', #optionsForLocal(7) == 1)
efExports.Remove(entityId)

local box = efExports.AddBoxZone({ coords = vec3(0, 0, 0), size = vec3(1, 1, 1), options = { label = 'B' } })
local sphere = efExports.AddSphereZone({ coords = vec3(0, 0, 0), radius = 1.0, options = { label = 'S' } })
local poly = efExports.AddPolyZone({ points = { vec3(0, 0, 0), vec3(1, 0, 0), vec3(0, 1, 0) }, options = { label = 'P' } })
check('zone exports build their kind', R.zones[box].kind == 'box' and R.zones[sphere].kind == 'sphere' and R.zones[poly].kind == 'poly')
check('zones belong to the caller', R.zones[box].resource == 'res_caller')
check('a box without a size is refused', not pcall(efExports.AddBoxZone, { coords = vec3(0, 0, 0), options = { label = 'B' } }))
efExports.Remove(box)
efExports.Remove(sphere)
efExports.Remove(poly)
check('Remove takes zones away', not R.zones[box] and not R.zones[sphere] and not R.zones[poly])

efExports.DisableTargeting(false)
check('DisableTargeting reaches the session', sessionDisabled == false)
sessionActive = false
check('IsActive reads the session', efExports.IsActive() == false)

-- A real resource under a provided name keeps its own exports
local function loadWithResource(name, probe)
    natives.GetNumResources = function() return 2 end
    natives.GetResourceByFindIndex = function(index) return index == 0 and 'ef_target' or name end
    events = {}
    local warned = countPrints(loadCompat)
    natives.GetNumResources = function() return 1 end
    natives.GetResourceByFindIndex = function() return 'ef_target' end
    return events[probe or '__cfx_export_ox_target_addModel'] ~= nil, warned
end

local served, warned = loadWithResource('ox_target')
check('real ox_target disables compat', served == false)
check('a real resource is reported in the console', warned == 2)
check('real ox_target also holds qtarget, it provides that name', loadWithResource('ox_target', '__cfx_export_qtarget_Ped') == false)
check('real ox_target leaves qb-target to compat', loadWithResource('ox_target', '__cfx_export_qb-target_AddTargetModel') == true)
check('real qb-target disables its own name', loadWithResource('qb-target', '__cfx_export_qb-target_AddTargetModel') == false)
check('real qb-target leaves ox_target to compat', loadWithResource('qb-target') == true)
check('real qtarget disables its own name', loadWithResource('qtarget', '__cfx_export_qtarget_Ped') == false)
check('an unrelated resource changes nothing', loadWithResource('ef_lib') == true)
natives.GetResourceByFindIndex = function() return nil end
events = {}
loadCompat()
check('a gap in the resource list is harmless', events['__cfx_export_ox_target_addModel'] ~= nil)
