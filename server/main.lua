-- Relays door toggles to the entity owner and tells every client when a tracked networked entity is gone.
-- Every argument comes from a client, so nothing is trusted until it has been checked here.
local TOGGLE_EVENT = 'ef_target:toggleDoor'
local TRACK_EVENT = 'ef_target:trackEntity'
local REMOVE_EVENT = 'ef_target:removeEntities'
local MAX_DISTANCE = 10.0
local MAX_DOOR = 5
local VEHICLE_TYPE = 2
local SWEEP_INTERVAL = 10000

local Server = {}
-- tracked[netId] = entity handle, kept so a deletion can be told apart from a netId that was never valid
local tracked = {}
local count = 0

local function isInteger(value)
    return math.type(value) == 'integer'
end

-- netId is only usable when it is an integer that resolves to a live entity
local function resolve(netId)
    if not isInteger(netId) then return nil end
    local handle = NetworkGetEntityFromNetworkId(netId)
    if not handle or handle == 0 or not DoesEntityExist(handle) then return nil end
    return handle
end

function Server.toggleDoor(source, netId, door)
    if not isInteger(source) or not isInteger(door) or door < 0 or door > MAX_DOOR then return end
    local vehicle = resolve(netId)
    if not vehicle or GetEntityType(vehicle) ~= VEHICLE_TYPE then return end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > MAX_DISTANCE then return end

    -- The owner is the only client whose door change replicates, so the request goes to it alone
    local owner = NetworkGetEntityOwner(vehicle)
    if not owner or owner == 0 then return end
    TriggerClientEvent(TOGGLE_EVENT, owner, netId, door)
end

function Server.trackEntity(source, netId)
    if not isInteger(source) then return end
    local handle = resolve(netId)
    if not handle or tracked[netId] == handle then return end
    -- A net id can be reused before the sweep ran, so a different handle replaces the stale claim
    if not tracked[netId] then count = count + 1 end
    tracked[netId] = handle
end

function Server.trackedCount() return count end

function Server.sweep()
    local gone = {}
    for netId, handle in pairs(tracked) do
        -- A handle can be recycled for another entity, so the net id has to still match
        if not DoesEntityExist(handle) or NetworkGetNetworkIdFromEntity(handle) ~= netId then
            gone[#gone + 1] = netId
        end
    end
    if #gone == 0 then return end
    for _, netId in ipairs(gone) do tracked[netId] = nil end
    count = count - #gone
    TriggerClientEvent(REMOVE_EVENT, -1, gone)
end

RegisterNetEvent(TOGGLE_EVENT, function(netId, door) Server.toggleDoor(source, netId, door) end)
RegisterNetEvent(TRACK_EVENT, function(netId) Server.trackEntity(source, netId) end)

-- Its own thread: an ef_lib without this export must not stop the relay from loading
CreateThread(function() exports.ef_lib:CheckVersion() end)

CreateThread(function()
    while true do
        Wait(SWEEP_INTERVAL)
        Server.sweep()
    end
end)

return Server
