-- Examples for the ef_target exports. Not loaded by the manifest: copy what you need into a client script of your own resource.

-- Point on a vehicle bone, visible while Alt is held (show defaults to 'alt')
local doorId = exports.ef_target:AddPoint({
    global = 'vehicle',
    bone = 'door_dside_f',
    distance = 2.0,
    label = 'Fahrertür',
    options = {
        {
            label = 'Tür abschließen',
            icon = 'fa-solid fa-lock',
            canInteract = function(entity, distance, coords, name, bone)
                return GetVehicleDoorLockStatus(entity) <= 1
            end,
            onSelect = function(data)
                SetVehicleDoorsLocked(data.entity, 2)
            end,
        },
    },
})

-- Point at world coordinates, always visible within 3 m. The nearest one shows a key pill, E runs the first option.
exports.ef_target:AddPoint({
    coords = vec3(-265.0, -963.6, 31.2),
    show = 'near',
    distance = 3.0,
    label = 'Jobcenter',
    options = {
        {
            label = 'Reden',
            icon = 'fa-solid fa-comments',
            onSelect = function(data)
                print(('Jobcenter, %.1f m entfernt'):format(data.distance))
            end,
        },
    },
})

-- Model: every ATM, with a restriction to a job
exports.ef_target:AddModel({ joaat('prop_atm_01'), joaat('prop_atm_02') }, {
    {
        label = 'Konto öffnen',
        icon = 'fa-solid fa-credit-card',
        groups = { police = 0, ambulance = 0 },
        distance = 1.5,
        serverEvent = 'myresource:openBank',
    },
})

-- Box zone: size is the full extent per axis, rotation turns it around Z
exports.ef_target:AddBoxZone({
    name = 'garage_desk',
    coords = vec3(-340.2, -131.0, 39.0),
    size = vec3(2.0, 1.0, 2.0),
    rotation = 70.0,
    options = {
        {
            label = 'Schlüssel abholen',
            icon = 'fa-solid fa-key',
            items = { garage_ticket = 1 },
            event = 'myresource:giveKeys',
        },
    },
})

-- Submenu: openMenu switches to the menu named in menuName, a back row is added on its own
exports.ef_target:AddGlobal('ped', {
    {
        label = 'Ausweis',
        icon = 'fa-solid fa-id-card',
        openMenu = 'ausweis',
    },
    {
        label = 'Zeigen',
        icon = 'fa-solid fa-eye',
        menuName = 'ausweis',
        onSelect = function(data) print('zeigen', data.entity) end,
    },
    {
        label = 'Kontrollieren',
        icon = 'fa-solid fa-magnifying-glass',
        menuName = 'ausweis',
        onSelect = function(data) print('kontrollieren', data.entity) end,
    },
})

-- Everything a resource adds goes when the resource stops. Remove takes one id earlier.
-- exports.ef_target:Remove(doorId)
