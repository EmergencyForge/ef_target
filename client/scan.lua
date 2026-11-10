-- Works out what the player aims at while a session runs: camera ray, fixed points around it and zones.
local Scan = {}
EFT.Scan = Scan

local SCAN_MS = 100
-- Rebuilding the points resolves every bone of every vehicle around, far too much for each scan.
-- The aimed point stays exact on its own, only the others on a moving vehicle step at this rate.
local COLLECT_MS = 150
-- Walking a game pool is the costly part of a scan and entities enter range slowly
local WALK_MS = 500
-- A point can sit half a long vehicle away from its origin, and the player keeps moving until the next walk
local REACH_MARGIN = 8.0
local FLAGS_ALL, FLAGS_ENTITIES = 511, 26
local IGNORE_NO_COLLISION = 4
local SHAPE_FAILED, SHAPE_PENDING = 0, 1
-- Doors and hoods sit inside the bodywork, so a sight ray ending this close to a point has reached it
local SIGHT_TOLERANCE = 1.0
-- Render reads a table without coords as "draw at the screen centre"
local CENTRE_AIM = {}
-- The surface under the crosshair only stands for a point it lies next to
local NORMAL_REACH = 1.0

-- Bumped on start and stop, a thread that sees another value is out of date
local generation = 0
local current = nil
local snappedKey = nil
local collected, collectedFor, collectedMenu, nextCollect = {}, nil, nil, 0
local known, walked, nextWalk, sightCursor = {}, {}, 0, 0
-- Answers of classify until the next pool walk, false for an entity that does not count
local classes = {}

local contains = { sphere = EFT.Geometry.inSphere, box = EFT.Geometry.inBox, poly = EFT.Geometry.inPoly }

local function readClass(entity)
    -- Rays can return handles the script host no longer knows
    local ok, entityType = pcall(GetEntityType, entity)
    if not ok or entityType == 0 then return false end
    local ped = PlayerPedId()
    if entity == ped or entity == GetVehiclePedIsIn(ped, false) then return false end
    local netId = NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity) or nil
    return { entityType, GetEntityModel(entity), netId, entityType == 1 and IsPedAPlayer(entity) }
end

function Scan.classify(entity)
    if not entity or entity == 0 then return nil end
    local class = classes[entity]
    if class == nil then
        class = readClass(entity)
        classes[entity] = class
    end
    if not class then return nil end
    return class[1], class[2], class[3], class[4]
end

-- Anything that is not a vehicle model may live in either of the other pools
local function gamePools(pools, show)
    local wanted = { CPed = pools.ped or pools.player, CVehicle = pools.vehicle, CObject = pools.object }
    if pools.model then
        for _, model in ipairs(EFT.Registry.pointKeys('model', show)) do
            if IsModelAVehicle(model) then
                wanted.CVehicle = true
            else
                wanted.CPed, wanted.CObject = true, true
            end
        end
    end
    return wanted
end

local function anchored(entries, show)
    local out = {}
    for _, entry in ipairs(entries) do
        if entry.anchor and (not show or entry.show == show) then out[#out + 1] = entry end
    end
    return out
end

local function reachOf(entries)
    local reach = 0.0
    for _, entry in ipairs(entries) do
        for _, option in ipairs(entry.options) do
            local distance = option.distance or Config.DefaultDistance
            if distance > reach then reach = distance end
        end
    end
    return reach
end

-- Entities in reach that carry points, pools are the result of Registry.nearPools or pointPools.
-- Only carriers come back, so everything that runs per scan stays clear of the bare entities in a pool.
-- A vehicle too far for any of its options would only have its bones read to be thrown away again.
function Scan.pointEntities(pools, show, center)
    classes = {}
    local out, seen = {}, {}
    local function add(entity)
        if seen[entity] then return end
        local distance = #(GetEntityCoords(entity) - center)
        if distance > Config.RayLength then return end
        seen[entity] = true
        local entityType, model, netId, isPlayer = Scan.classify(entity)
        if entityType then
            local entries = anchored(EFT.Registry.forEntity(entity, entityType, model, netId, isPlayer), show)
            if #entries > 0 and distance <= reachOf(entries) + REACH_MARGIN then out[#out + 1] = entity end
        end
    end
    for name, on in pairs(gamePools(pools, show)) do
        if on then
            for _, entity in ipairs(GetGamePool(name)) do add(entity) end
        end
    end
    if pools.entity then
        for _, id in ipairs(EFT.Registry.pointKeys('entity', show)) do
            if NetworkDoesNetworkIdExist(id) then add(NetworkGetEntityFromNetworkId(id)) end
        end
        for _, handle in ipairs(EFT.Registry.pointKeys('local', show)) do
            if DoesEntityExist(handle) then add(handle) end
        end
    end
    return out
end

-- Points of the given entities plus the free standing coords points. With show only entries of that mode take part.
function Scan.collectPoints(entities, show, playerCoords)
    local Registry, Points = EFT.Registry, EFT.Points
    local out = {}
    local function append(points)
        for _, point in ipairs(points) do out[#out + 1] = point end
    end
    for _, entity in ipairs(entities) do
        local entityType, model, netId, isPlayer = Scan.classify(entity)
        if entityType then
            append(Points.collect(entity, anchored(Registry.forEntity(entity, entityType, model, netId, isPlayer), show), playerCoords, model))
        end
    end
    append(Points.collect(nil, anchored(Registry.coordsEntries(), show), playerCoords))
    return out
end

-- Returns hit, entity, coords, status, surface normal
local function probe(from, to, flags, ignore)
    local handle = StartShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, flags, ignore, IGNORE_NO_COLLISION)
    while true do
        Wait(0)
        local status, hit, coords, normal, _, entity = GetShapeTestResultIncludingMaterial(handle)
        if status ~= SHAPE_PENDING then return hit == true or hit == 1, entity, coords, status, normal end
    end
end

-- Returns the entity under the crosshair, nil if there is none, and the hit position and normal, nil on a miss
local function cast(ped)
    local from, direction = GetWorldCoordFromScreenCoord(0.5, 0.5)
    local to = from + direction * Config.RayLength
    local hit, entity, coords, _, normal = probe(from, to, FLAGS_ALL, ped)
    if hit and Scan.classify(entity) then return entity, coords, normal end
    if not hit then coords, normal = nil, nil end

    local hit2, entity2, coords2, _, normal2 = probe(from, to, FLAGS_ENTITIES, ped)
    if not hit2 or (coords and #(coords2 - from) >= #(coords - from)) then return nil, coords, normal end
    if not Scan.classify(entity2) then return nil, coords2, normal2 end
    -- This flag set can reach through walls
    if HasEntityClearLosToEntity(entity2, ped, 7) then return entity2, coords2, normal2 end
    return nil, coords, normal
end

local function anyStatic(options, distance, menu)
    for _, option in ipairs(options) do
        if EFT.Filter.static(option, distance, menu) then return true end
    end
    return false
end

local function reachable(point, menu)
    for _, entry in ipairs(point.entries) do
        if anyStatic(entry.options, point.distance, menu) then return true end
    end
    return false
end

-- collect builds new tables each scan, the check results of a key have to move over.
-- Points that fail the static filter drop out before the limit: door points of every vehicle in range would crowd out the rest.
local function updatePoints(entity, playerCoords, now)
    if now >= nextWalk then
        nextWalk = now + WALK_MS
        walked = Scan.pointEntities(EFT.Registry.pointPools(), nil, playerCoords)
    end
    local menu = EFT.Session.menu()
    if now >= nextCollect or entity ~= collectedFor or menu ~= collectedMenu then
        nextCollect, collectedFor, collectedMenu = now + COLLECT_MS, entity, menu
        local entities = { entity }
        for _, other in ipairs(walked) do
            if other ~= entity then entities[#entities + 1] = other end
        end

        local fresh, points = {}, {}
        for _, point in ipairs(Scan.collectPoints(entities, nil, playerCoords)) do
            if reachable(point, menu) then
                local old = known[point.key]
                if old then point.visible, point.clear = old.visible, old.clear end
                fresh[point.key] = point
                points[#points + 1] = point
            end
        end
        known = fresh
        collected = EFT.Points.pick(points, Config.MaxPoints)
    end

    EFT.Points.refresh(collected, { playerCoords = playerCoords, menu = menu }, now)
    return collected
end

-- The centre of a zone without height limits says nothing about how far up the player stands
local function zoneCentre(zone, playerCoords)
    local center = zone.center
    if zone.openHeight then return vec3(center.x, center.y, playerCoords.z) end
    return center
end

-- What gets drawn, which is also all that can be snapped to
local function drawList(checked, playerCoords)
    local menu = EFT.Session.menu()
    local list = {}
    for _, point in ipairs(checked) do
        if point.visible and point.clear then list[#list + 1] = point end
    end
    for _, zone in ipairs(EFT.Registry.zoneGrid:near(playerCoords, Config.RayLength)) do
        local center = zoneCentre(zone, playerCoords)
        local distance = #(center - playerCoords)
        if zone.drawSprite ~= false and anyStatic(zone.options, distance, menu) then
            list[#list + 1] = { key = 'zone:' .. zone.id, coords = center, distance = distance, noSnap = true, visible = true }
        end
    end
    list = EFT.Points.pick(list, Config.MaxPoints)
    for _, point in ipairs(list) do
        if not point.noSnap then
            local c = point.coords
            local onScreen, x, y = GetScreenCoordFromWorldCoord(c.x, c.y, c.z)
            point.offScreen = not onScreen
            if onScreen then point.sx, point.sy = x, y else point.sx, point.sy = nil, nil end
        end
    end
    return list
end

local function zonesAt(coords)
    local out = {}
    if not coords then return out end
    for _, zone in ipairs(EFT.Registry.zoneGrid:near(coords, 0.0)) do
        if contains[zone.kind](zone, coords) then out[#out + 1] = zone end
    end
    return out
end

local function generalEntries(entity, entityType, model, netId, isPlayer)
    local out = {}
    for _, entry in ipairs(EFT.Registry.forEntity(entity, entityType, model, netId, isPlayer)) do
        if not entry.anchor then out[#out + 1] = entry end
    end
    return out
end

-- With a snap but no entity under the ray the point's entity stands in, so its general options stay reachable.
-- anchor is where the menu hangs, normal the surface it may lie on.
local function buildTarget(entity, coords, normal, playerCoords, zones, point)
    local hit = coords
    if point and not entity then
        entity, coords = point.entity, point.coords
    end
    if not entity and #zones == 0 and not point then return nil end

    local target = { zones = zones, point = point, entries = {}, coords = coords, distance = #(coords - playerCoords) }
    -- A ray inside a zone can end anywhere in it, behind a glass door on the floor: the menu hangs at its marker
    if point then target.anchor = point.coords
    elseif entity then target.anchor = coords
    else target.anchor = zoneCentre(zones[1], playerCoords) end
    target.holder = point and point.entity or entity
    if hit and normal and #(hit - target.anchor) <= NORMAL_REACH then target.normal = normal end
    local entityType, model, netId, isPlayer = Scan.classify(entity)
    if entityType then
        target.entity, target.entityType, target.model, target.netId = entity, entityType, model, netId
        target.entries = generalEntries(entity, entityType, model, netId, isPlayer)
    end
    return target
end

local function nextSight(candidates)
    for _, point in ipairs(candidates) do
        if point.clear == nil then return point end
    end
    sightCursor = sightCursor % #candidates + 1
    return candidates[sightCursor]
end

local function checkSight(checked, ped)
    local candidates = {}
    for _, point in ipairs(checked) do
        if point.visible then candidates[#candidates + 1] = point end
    end
    if #candidates == 0 then return end
    local point = nextSight(candidates)
    local hit, _, coords, status = probe(GetWorldCoordFromScreenCoord(0.5, 0.5), point.coords, FLAGS_ALL, ped)
    -- No answer is not a clear view, the last real one stands
    if status == SHAPE_FAILED then
        -- A point that never got an answer would otherwise stay first in the queue for good
        if point.clear == nil then point.clear = false end
        return
    end
    point.clear = not hit or #(coords - point.coords) < SIGHT_TOLERANCE
end

local function step(mine)
    local Session = EFT.Session
    local ped = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)
    local entity, coords, normal = cast(ped)
    -- The rays take frames and setAim has no guard of its own, so nothing may be drawn for a finished session
    if mine ~= generation or not Session.isActive() then return end

    local checked = updatePoints(entity, playerCoords, GetGameTimer())
    local drawn = drawList(checked, playerCoords)
    local point = EFT.Points.snap(drawn, Config.SnapRadius, GetAspectRatio(false), snappedKey)
    snappedKey = point and point.key
    if point and point.entity then point.coords = EFT.Points.resolve(point.entries[1], point.entity, point.model) or point.coords end

    current = buildTarget(entity, coords, normal, playerCoords, zonesAt(coords), point)
    Session.update(current)
    if not Session.isActive() then return end
    EFT.Render.setPoints(drawn)
    EFT.Render.setAim(point or CENTRE_AIM, Session.hasTarget())
    checkSight(checked, ped)
end

function Scan.start()
    generation = generation + 1
    local mine = generation
    -- known stays: the check results of the last press save the next one from starting at zero
    walked, nextWalk, current, snappedKey, classes = {}, 0, nil, nil, {}
    collected, collectedFor, collectedMenu, nextCollect = {}, nil, nil, 0
    CreateThread(function()
        while mine == generation and EFT.Session.isActive() do
            local started = GetGameTimer()
            step(mine)
            Wait(math.max(0, SCAN_MS - (GetGameTimer() - started)))
        end
    end)
end

function Scan.stop()
    generation = generation + 1
    current = nil
end

-- Near markers are on screen already, so a session takes them over as checked instead of blinking them off
function Scan.adopt(points)
    for _, point in ipairs(points) do
        point.visible, point.clear = true, true
        known[point.key] = point
    end
end

function Scan.current()
    return current
end
