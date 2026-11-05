local harness = require('tests.harness')
local check = harness.check
local vec3 = harness.vec3

local relayed, removed, entities, peds, owners = {}, {}, {}, {}, {}
local netIds = {}

harness.natives.RegisterNetEvent = function() end
harness.natives.AddEventHandler = function() end
harness.natives.CreateThread = function() end
harness.natives.TriggerClientEvent = function(event, target, a, b)
    if event == 'ef_target:toggleDoor' then
        relayed[#relayed + 1] = { target = target, netId = a, door = b }
    elseif event == 'ef_target:removeEntities' then
        removed[#removed + 1] = a
    end
end
harness.natives.NetworkGetEntityFromNetworkId = function(netId) return netIds[netId] or 0 end
harness.natives.NetworkGetNetworkIdFromEntity = function(handle)
    for netId, h in pairs(netIds) do if h == handle then return netId end end
    return 0
end
harness.natives.DoesEntityExist = function(handle) return handle ~= nil and handle ~= 0 and entities[handle] ~= nil end
harness.natives.GetEntityCoords = function(handle) return entities[handle] end
harness.natives.GetPlayerPed = function(source) return peds[source] or 0 end
harness.natives.NetworkGetEntityOwner = function(handle) return owners[handle] or 0 end

-- Handle 50 is networked as netId 5 and owned by player 8
entities[50], netIds[5], owners[50] = vec3(0, 0, 0), 50, 8
local function pedAt(source, coords) peds[source] = 900 + source; entities[900 + source] = coords end

local events = {}
harness.natives.RegisterNetEvent = function(name, fn) events[name] = fn end
local server = harness.load('server/main.lua')

local function door(source, netId, index) server.toggleDoor(source, netId, index) end
local function track(source, netId) server.trackEntity(source, netId) end
local function sweep() server.sweep() end

pedAt(1, vec3(2, 0, 0))
door(1, 'abc', 0); door(1, 5, 9); door(1, 404, 0)
check('bad door requests go nowhere', #relayed == 0)
door(1, 5, 1.5); door(1, 5, -1); door(nil, 5, 0); door(77, 5, 0)
check('fractional, negative, sourceless and pedless requests are refused', #relayed == 0)
pedAt(1, vec3(50, 0, 0)); door(1, 5, 0); check('a far player is refused', #relayed == 0)
pedAt(1, vec3(2, 0, 0)); door(1, 5, 0); check('a near player reaches the owner', relayed[1].target == 8)
check('the relay carries net id and door', relayed[1].netId == 5 and relayed[1].door == 0)

owners[50] = nil; door(1, 5, 0)
check('an entity without an owner relays nothing', #relayed == 1)
owners[50] = 8

check('the net events are registered', events['ef_target:toggleDoor'] ~= nil and events['ef_target:trackEntity'] ~= nil)

track(1, 'x'); track(1, 404)
check('junk is not tracked', server.trackedCount() == 0)
track(1, 5); check('a real entity is tracked', server.trackedCount() == 1)
entities[50] = nil; sweep()
check('a deleted entity is announced once', #removed == 1 and removed[1][1] == 5); sweep()
check('it is announced only once', #removed == 1)
check('it is forgotten after the announcement', server.trackedCount() == 0)

-- Same handle reused for a different net id must not keep the old claim alive
entities[50], netIds[5] = vec3(0, 0, 0), 50
track(1, 5); netIds[5] = nil; netIds[6] = 50; sweep()
check('a handle that changed net id counts as gone', #removed == 2 and removed[2][1] == 5)

for _, name in ipairs({ 'RegisterNetEvent', 'AddEventHandler', 'CreateThread', 'TriggerClientEvent', 'NetworkGetEntityFromNetworkId',
    'NetworkGetNetworkIdFromEntity', 'DoesEntityExist', 'GetEntityCoords', 'GetPlayerPed', 'NetworkGetEntityOwner' }) do
    _G[name] = nil
end
