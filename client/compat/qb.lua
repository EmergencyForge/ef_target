-- Serves qtarget and qb-target on top of the ox handlers, both share one parameter format.
-- Everything stays direct Lua calls so GetInvokingResource keeps naming the script that called.
local Compat = EFT.Compat
local Registry = EFT.Registry
local api = Compat.exportsFor('ox_target')
local caller, list = Compat.caller, Compat.list

-- PolyZones without bounds have no height limit, half a kilometre each way covers any map and interior
local OPEN_HEIGHT = 450.0

local handlers = {}
-- Entity zones are options on the entity, RemoveZone still has to find them by name
local entityZones = {}

local function translate(raw, distance)
    local option = {}
    for k, v in pairs(raw) do option[k] = v end
    option.onSelect = raw.action
    option.distance = raw.distance or distance
    option.name = raw.name or raw.label
    option.groups = raw.job
    option.items = raw.item or raw.required_item
    option.action, option.job, option.item, option.required_item = nil, nil, nil, nil
    -- Select hands these options the bare entity instead of the response table
    option.qtarget = true
    if raw.event and raw.type == 'server' then
        option.serverEvent, option.event, option.type = raw.event, nil, nil
    elseif raw.event and raw.type == 'command' then
        option.command, option.event, option.type = raw.event, nil, nil
    end
    return option
end

-- Scripts also pass options keyed by name, those follow the array part
function Compat.convert(params)
    local out = {}
    for _, raw in ipairs(params.options) do out[#out + 1] = translate(raw, params.distance) end
    for key, raw in pairs(params.options) do
        if type(key) ~= 'number' then out[#out + 1] = translate(raw, params.distance) end
    end
    return out
end

local convert = Compat.convert

local function heightRange(options, z)
    return options.minZ or z - OPEN_HEIGHT, options.maxZ or z + OPEN_HEIGHT
end

function handlers.AddBoxZone(name, center, length, width, options, targetoptions)
    local minZ, maxZ = heightRange(options, center.z)
    return api.addBoxZone({
        name = name,
        coords = vec3(center.x, center.y, (minZ + maxZ) / 2),
        size = vec3(width, length, math.abs(maxZ - minZ)),
        rotation = options.heading,
        options = convert(targetoptions),
    })
end

function handlers.AddPolyZone(name, points, options, targetoptions)
    local minZ, maxZ = heightRange(options, 0.0)
    local flat = {}
    for i, point in ipairs(points) do flat[i] = vec3(point.x, point.y, (minZ + maxZ) / 2) end
    return api.addPolyZone({
        name = name,
        points = flat,
        thickness = math.abs(maxZ - minZ),
        options = convert(targetoptions),
    })
end

function handlers.AddCircleZone(name, center, radius, _, targetoptions)
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

-- Ped, Vehicle and so on are the qtarget names, AddGlobalPed and so on the qb-target ones
for _, kind in ipairs({ 'Ped', 'Vehicle', 'Object', 'Player' }) do
    local add, remove = api['addGlobal' .. kind], api['removeGlobal' .. kind]
    local function addConverted(params) add(convert(params)) end
    handlers[kind], handlers['AddGlobal' .. kind] = addConverted, addConverted
    handlers['Remove' .. kind], handlers['RemoveGlobal' .. kind] = remove, remove
end

Compat.serve('qtarget', handlers)
Compat.serve('qb-target', handlers)
