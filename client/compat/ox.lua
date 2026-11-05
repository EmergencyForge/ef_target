-- Serves the ox_target exports. Scripts reach them through the provide entries of the manifest and the
-- export events below. Handlers call each other directly: a call through exports would make ef_target
-- the invoking resource, and the options would outlive the script that added them.
local Compat = {}
EFT.Compat = Compat

local Registry = EFT.Registry
local handlers = {}

local function realResources()
    local found = {}
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        if name then found[name] = true end
    end
    -- The real ox_target provides qtarget, two answers to one export would fight over it
    found.qtarget = found.qtarget or found.ox_target
    return found
end

local real = realResources()

-- GetResourceState would see our own provide, so a real resource only shows up in the resource list
function Compat.serve(name, exportTable)
    handlers[name] = exportTable
    if real[name] then
        print(('[ef_target] %s runs next to ef_target, its exports stay with it'):format(name))
        return
    end
    for export, fn in pairs(exportTable) do
        AddEventHandler(('__cfx_export_%s_%s'):format(name, export), function(setCB) setCB(fn) end)
    end
end

function Compat.exportsFor(name)
    return handlers[name]
end

-- Own calls have no invoker, they count as ef_target so name removal stays scoped
function Compat.caller()
    return GetInvokingResource() or GetCurrentResourceName()
end

function Compat.list(value)
    return type(value) == 'table' and value or { value }
end

function Compat.addModels(models, options, resource, extra)
    extra = extra or {}
    for _, model in ipairs(Compat.list(models)) do
        extra.id = Registry.add('model', tonumber(model) or joaat(model), options, resource, extra)
    end
    return extra.id
end

local caller, list = Compat.caller, Compat.list
local api = {}

-- ox wipes a key for every resource when no names are given, scripts may rely on that
local function removeFrom(kind, keys, names, resource)
    for _, key in ipairs(list(keys)) do
        if names then
            Registry.removeNames(kind, key, names, resource)
        else
            Registry.removeKey(kind, key)
        end
    end
end

-- The sizes are the defaults ox gets from ox_lib
function api.addBoxZone(data)
    data.type, data.size = 'box', data.size or vec3(2.0, 2.0, 2.0)
    return Registry.addZone(data, caller())
end

function api.addSphereZone(data)
    data.type, data.radius = 'sphere', data.radius or 2.0
    return Registry.addZone(data, caller())
end

function api.addPolyZone(data)
    data.type = 'poly'
    return Registry.addZone(data, caller())
end

function api.zoneExists(id)
    return Registry.zoneExists(id)
end

function api.removeZone(id, suppressWarning)
    if not Registry.removeZone(id) and not suppressWarning then
        print(('[ef_target] attempted to remove a zone that does not exist (id: %s)'):format(id))
    end
end

for key, suffix in pairs({ ped = 'Ped', vehicle = 'Vehicle', object = 'Object', player = 'Player' }) do
    api['addGlobal' .. suffix] = function(options)
        Registry.add('global', key, options, caller())
    end
    api['removeGlobal' .. suffix] = function(names)
        Registry.removeNames('global', key, names, caller())
    end
end

function api.addGlobalOption(options)
    Registry.add('global', 'any', options, caller())
end

function api.removeGlobalOption(names)
    Registry.removeNames('global', 'any', names, caller())
end

function api.addModel(models, options)
    Compat.addModels(models, options, caller())
end

function api.removeModel(models, names)
    local hashes = {}
    for i, model in ipairs(list(models)) do hashes[i] = tonumber(model) or joaat(model) end
    removeFrom('model', hashes, names, caller())
end

-- Registry.addEntity keys by netId again and tells the server, which a plain add would skip
function api.addEntity(netIds, options)
    local resource = caller()
    for _, netId in ipairs(list(netIds)) do
        if NetworkDoesNetworkIdExist(netId) then
            Registry.addEntity(NetworkGetEntityFromNetworkId(netId), options, resource)
        end
    end
end

function api.removeEntity(netIds, names)
    removeFrom('entity', netIds, names, caller())
end

function api.addLocalEntity(entities, options)
    local resource = caller()
    for _, entity in ipairs(list(entities)) do
        if DoesEntityExist(entity) then
            Registry.add('local', entity, options, resource)
        else
            print(('[ef_target] no entity with id %s exists in %s'):format(entity, resource))
        end
    end
end

function api.removeLocalEntity(entities, names)
    removeFrom('local', entities, names, caller())
end

local function entityOptions(entity, entityType, model)
    if IsPedAPlayer(entity) then return { global = Registry.optionsOf('global', 'player') or {} } end
    local netId = NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity)
    return {
        global = Registry.optionsOf('global', entityType == 1 and 'ped' or entityType == 2 and 'vehicle' or 'object') or {},
        model = Registry.optionsOf('model', model),
        entity = netId and Registry.optionsOf('entity', netId) or nil,
        localEntity = Registry.optionsOf('local', entity),
    }
end

-- Without an entity ox hands out its live options object, so the current target answers under those keys
function api.getTargetOptions(entity, entityType, model)
    if entity then return entityOptions(entity, entityType, model) end
    local target = EFT.Scan.current()
    local out = target and target.entity and entityOptions(target.entity, target.entityType, target.model) or {}
    out.globalTarget, out.global = out.global, nil
    out.__global = Registry.optionsOf('global', 'any') or {}
    return out
end

function api.disableTargeting(value)
    EFT.Session.disable(value)
end

function api.isActive()
    return EFT.Session.isActive()
end

Compat.serve('ox_target', api)
