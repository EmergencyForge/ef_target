local harness = require('tests.harness')
local check = harness.check

harness.resetEFT()
local onStop
_G.AddEventHandler = function(name, fn) if name == 'onResourceStop' then onStop = fn end end
harness.load('client/eft.lua')
harness.load('client/geometry.lua')
harness.load('client/registry.lua')
_G.AddEventHandler = nil
local R = EFT.Registry

local function labelsOf()
    local out = {}
    for _, entry in ipairs(R.forEntity(0, 0, 0, nil, false)) do
        for _, option in ipairs(entry.options) do out[#out + 1] = option.label end
    end
    return table.concat(out, ',')
end

local modelSeq = 1000
local function anchorOf(option)
    modelSeq = modelSeq + 1
    R.add('model', modelSeq, { option }, 'res_anchor')
    return R.forEntity(1, 3, modelSeq, nil, false)[1].anchor
end

R.add('model', 123, { label = 'A' }, 'res_a')
check('single option is wrapped', #R.forEntity(1, 3, 123, nil, false)[1].options == 1)
check('show defaults to alt', R.forEntity(1, 3, 123, nil, false)[1].show == 'alt')
R.add('global', 'vehicle', { { label = 'B', bones = { 'wheel_lf', 'wheel_rf' } } }, 'res_a')
local e = R.forEntity(2, 2, 999, nil, false)
check('a bone list gives one entry per bone', #e == 2 and e[1].anchor.bone == 'wheel_lf' and e[2].anchor.bone == 'wheel_rf')
check('split entries point back at their option', e[1].source == e[2].source and e[1].source.label == 'B'
    and e[1].options[1] ~= e[1].source)
check('anchored entries carry no source', (function()
    R.add('point', 'coords', { label = 'src' }, 'res_src', { anchor = { coords = vec3(0, 0, 0) } })
    local entry = R.coordsEntries()[1]
    R.removeResource('res_src')
    return entry.source == nil
end)())
check('a bone string gives one entry', anchorOf({ label = 'x', bones = 'door_dside_f' }).bone == 'door_dside_f')
check('old offsets are relative', anchorOf({ label = 'x', offset = vec3(0.5, 1, 0.5) }).relative == true)
check('absoluteOffset is kept', anchorOf({ label = 'x', offset = vec3(0, 1, 0), absoluteOffset = true }).relative == false)

R.add('global', 'any', { { name = 'x', label = 'C' } }, 'res_b')
R.add('global', 'any', { { name = 'x', label = 'D' } }, 'res_b')
check('same name replaces within a resource', labelsOf() == 'D')
R.add('global', 'any', { { name = 'x', label = 'E' } }, 'res_c')
check('same name in another resource stays', labelsOf() == 'D,E')
local anyList = R.forEntity(2, 2, 999, nil, false)
check('any entries are unlimited, typed ones are not', anyList[#anyList].unlimited == true and not anyList[1].unlimited)
R.removeNames('global', 'any', 'x', 'res_c')
check('removeNames is scoped to the resource', labelsOf() == 'D')

R.add('global', 'ped', { label = 'P' }, 'res_b')
R.add('global', 'player', { label = 'Q' }, 'res_b')
check('players skip the ped pool', #R.forEntity(5, 1, 1, nil, true) == 2 and #R.forEntity(5, 1, 1, nil, false) == 2)
R.add('entity', 77, { label = 'N' }, 'res_b')
R.add('local', 5, { label = 'L' }, 'res_b')
local order = R.forEntity(5, 1, 123, 77, false)
check('order is entity, local, model, type, any',
    order[1].options[1].label == 'N' and order[2].options[1].label == 'L' and order[3].options[1].label == 'A'
    and order[4].options[1].label == 'P' and order[5].options[1].label == 'D')

R.removeResource('res_a')
check('a stopped resource leaves nothing', #R.forEntity(1, 3, 123, nil, false) == 1)
local rev = R.revision
R.removeResource('res_a')
R.remove(99999)
check('a no-op removal keeps the revision', R.revision == rev)
local live = R.add('model', 124, { label = 'Z' }, 'res_d')
rev = R.revision
R.remove(live)
check('removal bumps the revision', R.revision > rev and #R.forEntity(1, 3, 124, nil, false) == 1)
check('bad options raise', not pcall(R.normalize, { foo = 1 }))
check('empty options raise', not pcall(R.normalize, {}))

local fn = function() end
R.add('model', 125, { label = 'F', onSelect = fn }, 'res_d')
check('funcrefs are stored as given', R.forEntity(1, 3, 125, nil, false)[1].options[1].onSelect == fn)

check('no near entries at first', not R.nearPools().vehicle and not R.nearPools().coords)
R.add('global', 'vehicle', { label = 'V' }, 'res_d', { show = 'near' })
R.add('point', 'coords', { label = 'C' }, 'res_d', { show = 'near', anchor = { coords = vec3(1, 2, 3) }, label = 'spot' })
local pools = R.nearPools()
check('nearPools sees vehicle and coords', pools.vehicle and pools.coords and not pools.ped and not pools.model)
local points = R.coordsEntries()
check('coordsEntries lists points', #points == 1 and points[1].anchor.coords.z == 3 and points[1].label == 'spot')
R.removeResource('res_d')
check('nearPools refreshes after removal', not R.nearPools().vehicle and #R.coordsEntries() == 0)

local zid = R.addZone({ name = 'z1', coords = vec3(0, 0, 0), radius = 2.0, options = { label = 'S' } }, 'res_z')
check('zone id is numeric and found by id and name', type(zid) == 'number' and R.zoneExists(zid) and R.zoneExists('z1'))
check('zone is in the grid', #R.zoneGrid:near(vec3(0, 0, 0), 5.0) == 1)
check('poly without points raises', not pcall(R.addZone, { type = 'poly', points = {}, options = { label = 'x' } }, 'res_z'))
check('box without size raises', not pcall(R.addZone, { type = 'box', coords = vec3(0, 0, 0), options = { label = 'x' } }, 'res_z'))
check('removeZone by name', R.removeZone('z1') and not R.zoneExists(zid) and #R.zoneGrid:near(vec3(0, 0, 0), 5.0) == 0)
check('removeZone on a missing zone is false', R.removeZone('z1') == false)
local z2 = R.addZone({ coords = vec3(0, 0, 0), size = vec3(2, 2, 2), options = { label = 'B' } }, 'res_z')
onStop('res_z')
check('onResourceStop drops zones too', not R.zoneExists(z2))
local twinA = R.addZone({ name = 'twin', coords = vec3(0, 0, 0), radius = 1.0, options = { label = 'A' } }, 'res_a')
local twinB = R.addZone({ name = 'twin', coords = vec3(0, 0, 0), radius = 1.0, options = { label = 'B' } }, 'res_b')
check('a name can hold several zones', R.zoneExists(twinA) and R.zoneExists(twinB))
R.removeResource('res_a')
check('a stopping resource takes only its twin', not R.zoneExists(twinA) and R.zoneExists('twin'))
R.addZone({ name = 'twin', coords = vec3(0, 0, 0), radius = 1.0, options = { label = 'C' } }, 'res_b')
check('removing by name takes all of them', R.removeZone('twin') and not R.zoneExists('twin') and not R.zoneExists(twinB))

local tracked = {}
-- Only labels from the entity and local buckets, global leftovers from earlier checks do not count
local function labelsFor(entity, netId)
    local out = {}
    for _, entry in ipairs(R.forEntity(entity, 0, 0, netId, false)) do
        for _, option in ipairs(entry.options) do out[#out + 1] = option.label end
    end
    return ',' .. table.concat(out, ',') .. ','
end
local function has(entity, netId, label) return labelsFor(entity, netId):find(',' .. label .. ',', 1, true) ~= nil end
harness.natives.NetworkGetEntityIsNetworked = function(entity) return entity >= 100 end
harness.natives.NetworkGetNetworkIdFromEntity = function(entity) return entity - 90 end
harness.natives.TriggerServerEvent = function(event, netId) tracked[#tracked + 1] = { event, netId } end
local timers = {}
harness.natives.SetTimeout = function(_, fn) timers[#timers + 1] = fn end
R.addEntity(100, { label = 'N' }, 'res_n')
R.addEntity(7, { label = 'L' }, 'res_n')
check('a networked entity is keyed by net id and reported', has(100, 10, 'N')
    and #tracked == 1 and tracked[1][1] == 'ef_target:trackEntity' and tracked[1][2] == 10)
for _, fn in ipairs(timers) do fn() end
check('the report is repeated once for a server that was not ready', #timers == 1 and #tracked == 2 and tracked[2][2] == 10)
check('a local entity is keyed by handle and not reported', has(7, nil, 'L') and #tracked == 2)
R.removeEntities({ 10, 11 })
check('removeEntities drops the net id entries only', not has(100, 10, 'N')
    and has(7, nil, 'L'))
for _, name in ipairs({ 'NetworkGetEntityIsNetworked', 'NetworkGetNetworkIdFromEntity', 'TriggerServerEvent', 'SetTimeout' }) do _G[name] = nil end

harness.resetEFT()
