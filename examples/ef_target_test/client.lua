-- Two rows of stations on the Sandy Shores runway. /eftest teleports there and back.
-- Everything is created locally per client, nothing here needs a server script.
local AREA = vec3(1640.0, 3222.0, 41.0)
-- Along the runway and across it
local ALONG, ACROSS = vec3(-0.95, -0.31, 0.0), vec3(0.31, -0.95, 0.0)
local STEP, ROW_GAP, PER_ROW = 8.0, 9.0, 8
local BUILD_RANGE, LABEL_RANGE = 150.0, 30.0

local target = exports.ef_target
local spawned, spots = {}, {}
local built, back = false, nil

local function say(text)
    return function() exports.ef_lib:SendNotification('success', 'ef_target', text, 2500) end
end

local function option(label, icon, extra)
    local row = extra or {}
    row.label, row.icon = label, 'fa-solid ' .. icon
    if not (row.openMenu or row.event or row.command) then row.onSelect = row.onSelect or say(label) end
    return row
end

local function above(spot, x, height)
    return spot + vec3(x, 0.0, height)
end

local function loadModel(name)
    local model = GetHashKey(name)
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end
    return model
end

local function keep(entity, model)
    spawned[#spawned + 1] = entity
    SetModelAsNoLongerNeeded(model)
    return entity
end

local function vehicleStation(spot)
    local model = loadModel('blista')
    local vehicle = keep(CreateVehicle(model, spot.x, spot.y, spot.z + 0.5, 0.0, false, false), model)
    SetVehicleOnGroundProperly(vehicle)

    target:AddPoint({
        entity = vehicle,
        bone = 'wheel_lf',
        label = 'Reifen vorne links',
        distance = 2.0,
        options = {
            option('Reifen prüfen', 'fa-circle-dot'),
            option('Reifen wechseln', 'fa-wrench', { hold = 2000 }),
        },
    })
    target:AddEntity(vehicle, {
        option('Abschließen oder aufschließen', 'fa-lock', {
            distance = 4.0,
            onSelect = function(data)
                local locked = GetVehicleDoorLockStatus(data.entity) > 1
                SetVehicleDoorsLocked(data.entity, locked and 1 or 2)
            end,
        }),
    })
end

local function altStation(spot)
    target:AddPoint({
        coords = above(spot, 0.0, 1.0),
        label = 'Fester Punkt',
        distance = 4.0,
        options = {
            option('Erste Option', 'fa-1'),
            option('Zweite Option', 'fa-2'),
            option('Dritte Option', 'fa-3'),
        },
    })
end

local function nearStation(spot)
    for i, x in ipairs({ -1.5, 1.5 }) do
        target:AddPoint({
            coords = above(spot, x, 1.0),
            show = 'near',
            label = 'Naher Punkt ' .. i,
            distance = 3.0,
            options = { option('Reden ' .. i, 'fa-comments') },
        })
    end
end

local function holdStation(spot)
    target:AddPoint({
        coords = above(spot, 0.0, 1.0),
        label = 'Halten',
        distance = 3.0,
        options = {
            option('Eine Sekunde halten', 'fa-hand', { hold = 1000 }),
            option('Drei Sekunden halten', 'fa-hand', { hold = 3000 }),
            option('Einfach klicken', 'fa-arrow-pointer'),
        },
    })
end

local function menuStation(spot)
    target:AddPoint({
        coords = above(spot, 0.0, 1.0),
        label = 'Untermenü',
        distance = 3.0,
        options = {
            option('Werkzeug', 'fa-toolbox', { openMenu = 'tools' }),
            option('Direkt ausführen', 'fa-bolt'),
            option('Hammer', 'fa-hammer', { menuName = 'tools' }),
            option('Noch tiefer', 'fa-folder-open', { menuName = 'tools', openMenu = 'deep' }),
            option('Zange', 'fa-screwdriver', { menuName = 'deep' }),
            option('Ganz nach oben', 'fa-house', { menuName = 'deep', openMenu = 'home' }),
        },
    })
end

local function longStation(spot)
    local rows = {}
    for i = 1, 14 do rows[i] = option('Zeile ' .. i, 'fa-list') end
    target:AddPoint({ coords = above(spot, 0.0, 1.0), label = 'Lange Liste', distance = 3.0, options = rows })
end

local function sphereStation(spot)
    target:AddSphereZone({
        coords = above(spot, 0.0, 1.0),
        radius = 1.5,
        label = 'Kugelzone',
        options = { option('In der Kugel', 'fa-circle') },
    })
end

local function boxStation(spot)
    target:AddBoxZone({
        coords = above(spot, 0.0, 1.0),
        size = vec3(3.0, 1.5, 2.0),
        rotation = 45.0,
        label = 'Boxzone',
        options = { option('In der Box', 'fa-square') },
    })
end

local function polyStation(spot)
    target:AddPolyZone({
        points = { above(spot, -2.0, 1.0), above(spot, 2.0, 1.0), spot + vec3(0.0, 2.5, 1.0) },
        thickness = 3.0,
        label = 'Polyzone',
        options = { option('Im Dreieck', 'fa-play') },
    })
end

-- Holds for every soda machine on the map, also the ones the game places itself
local function modelStation(spot)
    local name = 'prop_vend_soda_01'
    local model = loadModel(name)
    local prop = keep(CreateObject(model, spot.x, spot.y, spot.z, false, false, false), model)
    PlaceObjectOnGroundProperly(prop)
    FreezeEntityPosition(prop, true)

    target:AddModel(name, { option('Dose ziehen', 'fa-bottle-water', { distance = 2.5 }) })
    target:AddPoint({
        model = name,
        offset = vec3(0.0, -0.5, 1.2),
        label = 'Münzschlitz',
        distance = 2.5,
        options = { option('Münze einwerfen', 'fa-coins') },
    })
end

local function pedStation(spot)
    local model = loadModel('a_m_y_skater_01')
    local ped = keep(CreatePed(4, model, spot.x, spot.y, spot.z, 0.0, false, false), model)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    target:AddEntity(ped, { option('Ansprechen', 'fa-comment', { distance = 3.0 }) })
    target:AddPoint({
        entity = ped,
        bone = 'SKEL_Head',
        label = 'Kopf',
        distance = 3.0,
        options = { option('Kopf untersuchen', 'fa-user-doctor') },
    })
end

local function conditionStation(spot)
    local on = false
    target:AddPoint({
        coords = above(spot, -1.0, 1.0),
        label = 'Schalter',
        distance = 3.0,
        options = {
            option('Schalter umlegen', 'fa-toggle-on', { onSelect = function() on = not on end }),
            option('Nur wenn an', 'fa-eye', { canInteract = function() return on end }),
        },
    })
    target:AddPoint({
        coords = above(spot, 1.0, 1.0),
        label = 'Nur wenn an',
        distance = 3.0,
        options = { option('Dieser Punkt ist da', 'fa-eye', { canInteract = function() return on end }) },
    })
end

local function reachStation(spot)
    target:AddPoint({
        coords = above(spot, 0.0, 1.0),
        label = 'Reichweite',
        distance = 7.0,
        options = {
            option('Bis 7 m', 'fa-ruler'),
            option('Bis 4 m', 'fa-ruler', { distance = 4.0 }),
            option('Bis 2 m', 'fa-ruler', { distance = 2.0 }),
        },
    })
end

local function rightsStation(spot)
    target:AddPoint({
        coords = above(spot, 0.0, 1.0),
        label = 'Rechte',
        distance = 3.0,
        options = {
            option('Für alle', 'fa-users'),
            option('Nur police', 'fa-shield-halved', { groups = 'police' }),
        },
    })
end

local function runStation(spot)
    target:AddPoint({
        coords = above(spot, 0.0, 1.0),
        label = 'Ausführen',
        distance = 3.0,
        options = {
            option('Fortschrittsbalken', 'fa-spinner', {
                onSelect = function()
                    exports.ef_lib:ProgressBar({ label = 'Alt geht währenddessen nicht', duration = 3000, canCancel = true })
                end,
            }),
            option('Event', 'fa-bolt', { event = 'ef_target_test:ping' }),
            option('Befehl', 'fa-terminal', { command = 'eftest_ping' }),
        },
    })
end

local function compatStation(spot)
    exports.ox_target:addSphereZone({
        coords = above(spot, -2.0, 1.0),
        radius = 1.0,
        options = { { label = 'Aus ox_target', icon = 'fa-solid fa-cube', onSelect = say('ox_target') } },
    })
    exports['qb-target']:AddCircleZone('ef_target_test_qb', above(spot, 2.0, 1.0), 1.0, { name = 'ef_target_test_qb', useZ = true }, {
        options = { { label = 'Aus qb-target', icon = 'fa-solid fa-cube', action = say('qb-target') } },
        distance = 2.5,
    })
end

local stations = {
    { 'Fahrzeug', 'Alt halten: Türen, Haube, Kofferraum, Reifen', vehicleStation },
    { 'Punkt mit Alt', 'Alt halten, Raute anvisieren, Mausrad, Klick oder E', altStation },
    { 'Punkte in der Nähe', 'Ohne Alt sichtbar, E am nächsten Punkt', nearStation },
    { 'Halten', 'Klick oder E gedrückt halten, loslassen bricht ab', holdStation },
    { 'Untermenü', 'Klick geht rein, Rechtsklick zurück', menuStation },
    { 'Lange Liste', 'Mausrad scrollt die Zeilen', longStation },
    { 'Kugelzone', 'Raute in die Zone halten', sphereStation },
    { 'Boxzone', 'Um 45 Grad gedreht', boxStation },
    { 'Polyzone', 'Dreieck', polyStation },
    { 'Modell', 'Gilt für jeden Automaten auf der Karte', modelStation },
    { 'Ped', 'Entity plus Punkt am Kopf', pedStation },
    { 'Bedingung', 'canInteract blendet Zeile und Punkt aus', conditionStation },
    { 'Reichweite', 'Näher ran, mehr Zeilen', reachStation },
    { 'Rechte', 'Eine Zeile nur für police', rightsStation },
    { 'Ausführen', 'Fortschritt, Event, Befehl', runStation },
    { 'Kompatibilität', 'Links ox_target, rechts qb-target', compatStation },
}

local function groundAt(x, y)
    RequestCollisionAtCoord(x, y, AREA.z)
    for _ = 1, 40 do
        local found, z = GetGroundZFor_3dCoord(x, y, AREA.z + 20.0, false)
        if found then return z end
        Wait(50)
    end
    return AREA.z
end

local function slot(index)
    local column = (index - 1) % PER_ROW
    local row = (index - 1) // PER_ROW
    local offset = ALONG * ((column - (PER_ROW - 1) / 2) * STEP) + ACROSS * ((row - 0.5) * ROW_GAP)
    return AREA.x + offset.x, AREA.y + offset.y
end

local function build()
    built = true
    for i, station in ipairs(stations) do
        local x, y = slot(i)
        local spot = vec3(x, y, groundAt(x, y))
        spots[i] = spot
        -- One broken station must not take the rest of the area with it
        local ok, err = pcall(station[3], spot)
        if not ok then print(('[ef_target_test] %s: %s'):format(station[1], err)) end
    end
end

local function drawLabel(spot, title, hint)
    SetDrawOrigin(spot.x, spot.y, spot.z + 2.6, 0)
    SetTextScale(0.0, 0.42)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(title)
    EndTextCommandDisplayText(0.0, 0.0)
    SetTextScale(0.0, 0.3)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(hint)
    EndTextCommandDisplayText(0.0, 0.03)
    ClearDrawOrigin()
end

local function drawStations(playerCoords)
    for i, spot in pairs(spots) do
        if #(playerCoords - spot) < LABEL_RANGE then
            DrawMarker(25, spot.x, spot.y, spot.z + 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.2, 1.0,
                255, 255, 255, 70, false, false, 2, false, nil, nil, false)
            drawLabel(spot, stations[i][1], stations[i][2])
        end
    end
end

-- Sleeps away from the area, so the resource stays quiet in resmon unless someone stands in it
CreateThread(function()
    while true do
        local playerCoords = GetEntityCoords(PlayerPedId())
        if #(playerCoords - AREA) < BUILD_RANGE then
            if not built then build() end
            drawStations(playerCoords)
            Wait(0)
        else
            Wait(1000)
        end
    end
end)

local blip = AddBlipForCoord(AREA.x, AREA.y, AREA.z)
SetBlipSprite(blip, 1)
SetBlipColour(blip, 5)
BeginTextCommandSetBlipName('STRING')
AddTextComponentSubstringPlayerName('ef_target Testgelände')
EndTextCommandSetBlipName(blip)

RegisterCommand('eftest', function()
    local ped = PlayerPedId()
    local here = GetEntityCoords(ped)
    if back and #(here - AREA) < BUILD_RANGE then
        SetEntityCoords(ped, back.x, back.y, back.z, false, false, false, false)
        back = nil
        return
    end
    back = here
    -- Frozen until the ground exists, otherwise the player falls through the runway
    FreezeEntityPosition(ped, true)
    SetEntityCoords(ped, AREA.x, AREA.y, AREA.z + 1.0, false, false, false, false)
    local ground = groundAt(AREA.x, AREA.y)
    SetEntityCoords(ped, AREA.x, AREA.y, ground + 1.0, false, false, false, false)
    FreezeEntityPosition(ped, false)
end, false)

AddEventHandler('ef_target_test:ping', say('Event angekommen'))
RegisterCommand('eftest_ping', say('Befehl angekommen'), false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, entity in ipairs(spawned) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
    RemoveBlip(blip)
end)
