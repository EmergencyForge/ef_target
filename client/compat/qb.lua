-- Serves qtarget and qb-target on top of the ox handlers, both share one parameter format.
-- Everything stays direct Lua calls so GetInvokingResource keeps naming the script that called.
local Compat = EFT.Compat
local Framework = EFT.Framework
local Registry = EFT.Registry
local api = Compat.exportsFor('ox_target')
local caller, list = Compat.caller, Compat.list

-- PolyZones without bounds have no height limit, half a kilometre each way covers any map and interior
local OPEN_HEIGHT = 450.0

local handlers = {}
-- Entity zones are options on the entity, RemoveZone still has to find them by name
local entityZones = {}

local function copy(source)
    local out = {}
    for k, v in pairs(source) do out[k] = v end
    return out
end

-- The string 'all' is no requirement in qb. Tables stay: qb looks them up by the player's job, 'all' means nothing there.
local function withoutAll(filter)
    if filter ~= 'all' then return filter end
end

local function inGroup(filter)
    return filter == 'all' or Framework.hasGroup(filter)
end

local function matches(filter, value)
    if type(filter) == 'table' then return filter[value] and true or false end
    return filter == value
end

-- The fields groups and items do not cover, all ANDed as in qb. Filter stays free of them through this closure.
local function buildGuard(raw, gang, jobType)
    local excludejob, excludegang, excludejobType, citizenid = raw.excludejob, raw.excludegang, raw.excludejobType, raw.citizenid
    if not (gang or jobType or excludejob or excludegang or excludejobType or citizenid) then return nil end
    return function()
        -- Not the open rule of groups and items: these options name specific people
        if not Framework.name then return false end
        if gang and not Framework.hasGroup(gang) then return false end
        if excludejob and inGroup(excludejob) then return false end
        if excludegang and inGroup(excludegang) then return false end
        local currentType = Framework.jobType()
        if jobType and not matches(jobType, currentType) then return false end
        if excludejobType and (not currentType or excludejobType == 'all' or matches(excludejobType, currentType)) then return false end
        if citizenid and not matches(citizenid, Framework.citizenId()) then return false end
        return true
    end
end

-- Own onSelect: this event takes two arguments, the serverEvent path of Select sends one
local function callCommand(raw)
    return function(entity)
        local data = copy(raw)
        data.entity = entity
        TriggerServerEvent('QBCore:CallCommand', raw.event, data)
    end
end

local function translate(raw, outer)
    local option = copy(raw)
    option.onSelect = raw.action
    option.distance = math.min(raw.distance or outer, outer)
    option.name = raw.name or raw.label
    option.groups = withoutAll(raw.job)
    option.items = raw.required_item or raw.item
    option.guard = buildGuard(raw, withoutAll(raw.gang), withoutAll(raw.jobType))
    option.action, option.job, option.item, option.required_item = nil, nil, nil, nil
    -- qtarget: Select hands the bare entity. qbInteract: Filter hands canInteract the option.
    option.qtarget, option.qbInteract = true, true
    if raw.event and raw.type == 'server' then
        option.serverEvent, option.event, option.type = raw.event, nil, nil
    elseif raw.event and raw.type == 'command' then
        option.command, option.event, option.type = raw.event, nil, nil
    elseif raw.event and raw.type == 'qbcommand' then
        option.onSelect, option.event, option.type = raw.action or callCommand(raw), nil, nil
    end
    return option
end

-- Scripts also pass options keyed by name, those follow the array part
function Compat.convert(params)
    local given, outer = params.options or {}, params.distance or Config.DefaultDistance
    local out = {}
    for _, raw in ipairs(given) do out[#out + 1] = translate(raw, outer) end
    for key, raw in pairs(given) do
        if type(key) ~= 'number' then out[#out + 1] = translate(raw, outer) end
    end
    return out
end

local convert = Compat.convert

-- A single bound counts as open: honouring it would move the centre, and the marker with it, far off
local function heightRange(options, z)
    if options.minZ and options.maxZ then return options.minZ, options.maxZ, nil end
    return z - OPEN_HEIGHT, z + OPEN_HEIGHT, true
end

function handlers.AddBoxZone(name, center, length, width, options, targetoptions)
    local minZ, maxZ, open = heightRange(options, center.z)
    handlers.RemoveZone(name)
    return api.addBoxZone({
        name = name,
        coords = vec3(center.x, center.y, (minZ + maxZ) / 2),
        size = vec3(width, length, math.abs(maxZ - minZ)),
        rotation = options.heading,
        openHeight = open,
        options = convert(targetoptions),
    })
end

function handlers.AddPolyZone(name, points, options, targetoptions)
    -- Reading z off a vector2 is not safe, qb takes those as well
    local first = points[1]
    local minZ, maxZ, open = heightRange(options, type(first) ~= 'vector2' and first.z or 0.0)
    local flat = {}
    for i, point in ipairs(points) do flat[i] = vec3(point.x, point.y, (minZ + maxZ) / 2) end
    handlers.RemoveZone(name)
    return api.addPolyZone({
        name = name,
        points = flat,
        thickness = math.abs(maxZ - minZ),
        openHeight = open,
        options = convert(targetoptions),
    })
end

function handlers.AddCircleZone(name, center, radius, _, targetoptions)
    handlers.RemoveZone(name)
    return api.addSphereZone({
        name = name,
        coords = center,
        radius = radius,
        options = convert(targetoptions),
    })
end

function handlers.RemoveZone(id)
    local entityZone = entityZones[id]
    if entityZone then
        entityZones[id] = nil
        return Registry.remove(entityZone)
    end
    api.removeZone(id, true)
end

-- Zones here do not move, so the options go on the entity the zone would follow
function handlers.AddEntityZone(name, entity, _, targetoptions)
    handlers.RemoveZone(name)
    entityZones[name] = Registry.addEntity(entity, convert(targetoptions), caller())
    return entityZones[name]
end

function handlers.AddTargetBone(bones, params)
    local options = convert(params)
    for _, option in ipairs(options) do option.bones = bones end
    api.addGlobalVehicle(options)
end

function handlers.RemoveTargetBone(bones, labels)
    Registry.removeBones('global', 'vehicle', bones, labels, GetCurrentResourceName())
end

function handlers.AddTargetEntity(entities, params)
    local options, resource = convert(params), caller()
    for _, entity in ipairs(list(entities)) do Registry.addEntity(entity, options, resource) end
end

function handlers.RemoveTargetEntity(entities, labels)
    for _, entity in ipairs(list(entities)) do
        if NetworkGetEntityIsNetworked(entity) then
            api.removeEntity(NetworkGetNetworkIdFromEntity(entity), labels)
        else
            api.removeLocalEntity(entity, labels)
        end
    end
end

function handlers.AddTargetModel(models, params)
    api.addModel(models, convert(params))
end

function handlers.RemoveTargetModel(models, labels)
    api.removeModel(models, labels)
end

-- Position of the parameter table per export
local paramsAt = { AddBoxZone = 6, AddPolyZone = 4, AddCircleZone = 5, AddEntityZone = 4, AddTargetBone = 2, AddTargetEntity = 2, AddTargetModel = 2 }

-- Ped, Vehicle and so on are the qtarget names, AddGlobalPed and so on the qb-target ones
for _, kind in ipairs({ 'Ped', 'Vehicle', 'Object', 'Player' }) do
    local add, remove, key = api['addGlobal' .. kind], api['removeGlobal' .. kind], kind:lower()
    local function addConverted(params) add(convert(params)) end
    handlers[kind], handlers['AddGlobal' .. kind] = addConverted, addConverted
    handlers['Remove' .. kind] = remove
    handlers['RemoveGlobal' .. kind] = function(labels)
        if labels then return remove(labels) end
        Registry.removeKey('global', key, GetCurrentResourceName())
    end
    paramsAt[kind], paramsAt['AddGlobal' .. kind] = 1, 1
end

-- qb takes an empty list without complaint, the registry refuses one
for name, index in pairs(paramsAt) do
    local add = handlers[name]
    handlers[name] = function(...)
        local params = select(index, ...)
        if next(params.options or {}) ~= nil then return add(...) end
    end
end

Compat.serve('qtarget', handlers)
Compat.serve('qb-target', handlers)
