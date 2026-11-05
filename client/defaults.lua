-- Built-in vehicle points on the four doors, the hood and the trunk.
if not Config.DefaultPoints then return end

local REACH = 2.0
local TOGGLE_EVENT = 'ef_target:toggleDoor'

local function doorAllowed(vehicle, door)
    return GetIsDoorValid(vehicle, door) and GetVehicleDoorLockStatus(vehicle) <= 1
        and not IsVehicleDoorDamaged(vehicle, door) and GetVehiclePedIsIn(PlayerPedId(), false) == 0
end

-- A relayed request comes straight from another client, so the owner has to look at the lock again
local function toggle(vehicle, door)
    if GetVehicleDoorLockStatus(vehicle) > 1 then return end
    if GetVehicleDoorAngleRatio(vehicle, door) > 0.0 then
        SetVehicleDoorShut(vehicle, door, false)
    else
        SetVehicleDoorOpen(vehicle, door, false, false)
    end
end

-- Door state only sticks on the entity owner, everything else goes through the server
local function useDoor(vehicle, door)
    if not NetworkGetEntityIsNetworked(vehicle) or NetworkGetEntityOwner(vehicle) == PlayerId() then
        toggle(vehicle, door)
    else
        TriggerServerEvent(TOGGLE_EVENT, NetworkGetNetworkIdFromEntity(vehicle), door)
    end
end

local points = {
    { door = 0, label = 'Fahrertür', icon = 'fa-solid fa-car-side', anchor = { bone = 'handle_dside_f', fallback = 'door_dside_f' } },
    { door = 1, label = 'Beifahrertür', icon = 'fa-solid fa-car-side', anchor = { bone = 'handle_pside_f', fallback = 'door_pside_f' } },
    { door = 2, label = 'Tür hinten links', icon = 'fa-solid fa-car-side', anchor = { bone = 'handle_dside_r', fallback = 'door_dside_r' } },
    { door = 3, label = 'Tür hinten rechts', icon = 'fa-solid fa-car-side', anchor = { bone = 'handle_pside_r', fallback = 'door_pside_r' } },
    { door = 4, label = 'Motorhaube', icon = 'fa-solid fa-car', anchor = { offset = vec3(0.5, 1, 0.5), relative = true } },
    { door = 5, label = 'Kofferraum', icon = 'fa-solid fa-car-rear', anchor = { offset = vec3(0.5, 0, 0.5), relative = true } },
}

for _, point in ipairs(points) do
    local door = point.door
    EFT.Registry.add('global', 'vehicle', {
        name = 'ef_target:door' .. door,
        label = L('Öffnen/Schließen'),
        icon = point.icon,
        distance = REACH,
        canInteract = function(entity) return doorAllowed(entity, door) end,
        onSelect = function(data) useDoor(data.entity, door) end,
    }, GetCurrentResourceName(), { anchor = point.anchor, label = L(point.label) })
end

RegisterNetEvent(TOGGLE_EVENT, function(netId, door)
    local vehicle = NetToVeh(netId)
    if DoesEntityExist(vehicle) then toggle(vehicle, door) end
end)
