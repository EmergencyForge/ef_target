-- Central store of every target option. Later modules only read it through forEntity, the zone grid and the helpers below.
-- Plain Lua apart from the guarded onResourceStop hook, so tests run it outside FiveM.
local Registry = { revision = 0, zones = {}, zoneGrid = EFT.Geometry.grid() }
EFT.Registry = Registry

local nextId = 0
-- buckets[kind][key] = entry[]; kind is global, model, entity, local or point
local buckets = { global = {}, model = {}, entity = {}, ['local'] = {}, point = {} }
local zonesByName = {}
local poolCache = {}

local function bump() Registry.revision = Registry.revision + 1 end

local function newId()
    nextId = nextId + 1
    return nextId
end

-- Accepts one option (has a label) or an array of options; stored as given because funcrefs must survive
function Registry.normalize(options)
    if type(options) ~= 'table' then error('target options must be a table', 2) end
    if options.label ~= nil then return { options } end
    if #options == 0 then error('target options need a label or a non-empty array of options', 2) end
    for i = 1, #options do
        if type(options[i]) ~= 'table' then error('target option ' .. i .. ' is not a table', 2) end
    end
    return options
end

-- fn(entry, kind, key) returns keep and edited. Bumps the revision only on a real change.
local function purge(fn, onlyKind, onlyKey)
    local changed = false
    for kind, byKey in pairs(buckets) do
        if not onlyKind or kind == onlyKind then
            for key, list in pairs(byKey) do
                if onlyKey == nil or key == onlyKey then
                    local kept = {}
                    for _, entry in ipairs(list) do
                        local keep, edited = fn(entry, kind, key)
                        if keep then kept[#kept + 1] = entry end
                        if not keep or edited then changed = true end
                    end
                    byKey[key] = #kept > 0 and kept or nil
                end
            end
        end
    end
    if changed then bump() end
    return changed
end

function Registry.removeNames(kind, key, names, resource)
    if type(names) ~= 'table' then names = { names } end
    local drop = {}
    for _, name in ipairs(names) do drop[name] = true end
    purge(function(entry)
        if resource ~= nil and entry.resource ~= resource then return true end
        local left = {}
        for _, option in ipairs(entry.options) do
            if not (option.name ~= nil and drop[option.name]) then left[#left + 1] = option end
        end
        if #left == #entry.options then return true end
        entry.options = left
        return #left > 0, true
    end, kind, key)
end

function Registry.remove(id)
    purge(function(entry) return entry.id ~= id end)
end

function Registry.removeResource(resource)
    purge(function(entry) return entry.resource ~= resource end)
    local zoneIds = {}
    for id, zone in pairs(Registry.zones) do
        if zone.resource == resource then zoneIds[#zoneIds + 1] = id end
    end
    for _, id in ipairs(zoneIds) do Registry.removeZone(id) end
end

local function copyOption(option)
    local copy = {}
    for k, v in pairs(option) do copy[k] = v end
    return copy
end

-- extra.anchor puts every option on one anchor. Otherwise bones and offset split an option into one entry per anchor.
local function buildEntries(id, resource, options, extra)
    local show = extra.show or 'alt'
    -- source is the option an entry was split from, so points can merge close anchors of one option only
    local function entry(list, anchor, source)
        return { id = id, resource = resource, options = list, anchor = anchor, show = show, label = extra.label, source = source }
    end
    if extra.anchor then return { entry(options, extra.anchor) } end

    local plain, entries = {}, {}
    for _, option in ipairs(options) do
        local bones = option.bones
        if type(bones) == 'string' then bones = { bones } end
        if bones then
            for _, bone in ipairs(bones) do
                entries[#entries + 1] = entry({ copyOption(option) }, { bone = bone }, option)
            end
        elseif option.offset then
            entries[#entries + 1] = entry({ copyOption(option) }, { offset = option.offset, relative = not option.absoluteOffset }, option)
        else
            plain[#plain + 1] = option
        end
    end
    if #plain > 0 then table.insert(entries, 1, entry(plain, nil)) end
    return entries
end

-- key: global type, model hash, netId or entity handle, 'coords' for points
function Registry.add(kind, key, options, resource, extra)
    if not buckets[kind] then error('unknown target kind ' .. tostring(kind), 2) end
    options = Registry.normalize(options)
    extra = extra or {}

    local names = {}
    for _, option in ipairs(options) do
        if option.name ~= nil then names[#names + 1] = option.name end
    end
    if #names > 0 then Registry.removeNames(kind, key, names, resource) end

    -- extra.id joins several keys under one id, so one Remove covers a whole model list
    local id = extra.id or newId()
    local list = buckets[kind][key]
    if not list then list = {}; buckets[kind][key] = list end
    for _, entry in ipairs(buildEntries(id, resource, options, extra)) do
        -- Global any options have no distance limit, like addGlobalOption in ox_target
        if kind == 'global' and key == 'any' then entry.unlimited = true end
        list[#list + 1] = entry
    end
    bump()
    if extra.show == 'near' and Registry.onNearAdded then Registry.onNearAdded() end
    return id
end

-- Networked entities are keyed by net id so every client resolves them alike, the rest by local handle.
-- The server is told about networked ones so it can announce their deletion.
function Registry.addEntity(entity, options, resource, extra)
    if NetworkGetEntityIsNetworked(entity) then
        local netId = NetworkGetNetworkIdFromEntity(entity)
        TriggerServerEvent('ef_target:trackEntity', netId)
        -- The server may not know a fresh entity yet and drops the first report, it dedupes the second
        SetTimeout(2000, function() TriggerServerEvent('ef_target:trackEntity', netId) end)
        return Registry.add('entity', netId, options, resource, extra)
    end
    return Registry.add('local', entity, options, resource, extra)
end

function Registry.removeKey(kind, key)
    purge(function() return false end, kind, key)
end

function Registry.removeEntities(netIds)
    for _, netId in ipairs(netIds) do Registry.removeKey('entity', netId) end
end

-- The options on one key, nil when there are none. An option split over several bones counts once.
function Registry.optionsOf(kind, key)
    local list = buckets[kind][key]
    if not list then return nil end
    local out, seen = {}, {}
    for _, entry in ipairs(list) do
        for _, option in ipairs(entry.source and { entry.source } or entry.options) do
            if not seen[option] then
                seen[option] = true
                out[#out + 1] = option
            end
        end
    end
    return out
end

local function append(out, list)
    if list then for _, entry in ipairs(list) do out[#out + 1] = entry end end
end

local typeKey = { [1] = 'ped', [2] = 'vehicle', [3] = 'object' }

-- Order: entity then local, model, global by type, any
function Registry.forEntity(entity, entityType, model, netId, isPlayer)
    local out = {}
    if netId then append(out, buckets.entity[netId]) end
    append(out, buckets['local'][entity])
    append(out, buckets.model[model])
    append(out, buckets.global[isPlayer and 'player' or typeKey[entityType]])
    append(out, buckets.global.any)
    return out
end

function Registry.coordsEntries()
    local out = {}
    append(out, buckets.point.coords)
    return out
end

-- Without show every entry with an anchor counts: an alt scan also shows near points
local function matches(entry, show)
    if show then return entry.show == show end
    return entry.anchor ~= nil
end

-- Where matching entries exist, so point scans only walk pools that can matter
local function poolsFor(show)
    local cached = poolCache[show or 'any']
    if cached and cached.revision == Registry.revision then return cached.pools end
    local pools = { ped = false, vehicle = false, object = false, player = false, model = false, coords = false, entity = false }
    local poolOf = { model = 'model', entity = 'entity', ['local'] = 'entity', point = 'coords' }
    for kind, byKey in pairs(buckets) do
        for key, list in pairs(byKey) do
            for _, entry in ipairs(list) do
                if matches(entry, show) then
                    if kind ~= 'global' then
                        pools[poolOf[kind]] = true
                    elseif key == 'any' then
                        pools.ped, pools.vehicle, pools.object, pools.player = true, true, true, true
                    else
                        pools[key] = true
                    end
                end
            end
        end
    end
    poolCache[show or 'any'] = { revision = Registry.revision, pools = pools }
    return pools
end

function Registry.nearPools() return poolsFor('near') end
function Registry.pointPools() return poolsFor(nil) end

-- Keys of a kind that hold matching entries: model hashes, netIds or entity handles
function Registry.pointKeys(kind, show)
    local keys = {}
    for key, list in pairs(buckets[kind]) do
        for _, entry in ipairs(list) do
            if matches(entry, show) then
                keys[#keys + 1] = key
                break
            end
        end
    end
    return keys
end

-- Zones keep ox field names; type is optional and inferred from points or size
function Registry.addZone(zone, resource)
    if type(zone) ~= 'table' then error('zone must be a table', 2) end
    local kind = zone.type or (zone.points and 'poly') or (zone.size and 'box') or 'sphere'
    if kind == 'poly' then
        if type(zone.points) ~= 'table' or #zone.points < 3 then error('poly zone needs at least 3 points', 2) end
    else
        if kind == 'box' and not zone.size then error('box zone needs a size', 2) end
        if not zone.coords then error(kind .. ' zone needs coords', 2) end
    end
    local copy = {}
    for k, v in pairs(zone) do copy[k] = v end
    copy.options = Registry.normalize(zone.options)
    -- Scripts also pass vector4 and plain tables, and the scan does vector math on the centre
    local c = zone.coords
    if c then copy.coords = vec3(c.x or c[1], c.y or c[2], c.z or c[3]) end
    if copy.name ~= nil and zonesByName[copy.name] then Registry.removeZone(copy.name) end
    copy.id, copy.resource = newId(), resource

    Registry.zoneGrid:add(EFT.Geometry.prepare(copy))
    Registry.zones[copy.id] = copy
    if copy.name ~= nil then zonesByName[copy.name] = copy.id end
    bump()
    return copy.id
end

local function findZone(idOrName)
    return Registry.zones[idOrName] or Registry.zones[zonesByName[idOrName]]
end

function Registry.zoneExists(idOrName)
    return findZone(idOrName) ~= nil
end

function Registry.removeZone(idOrName)
    local zone = findZone(idOrName)
    if not zone then return false end
    Registry.zoneGrid:remove(zone)
    Registry.zones[zone.id] = nil
    if zone.name ~= nil then zonesByName[zone.name] = nil end
    bump()
    return true
end

-- Outside FiveM there is no event system, the guard keeps the file loadable in tests
if AddEventHandler then
    AddEventHandler('onResourceStop', function(resource) Registry.removeResource(resource) end)
end
if RegisterNetEvent then
    RegisterNetEvent('ef_target:removeEntities', function(netIds)
        if type(netIds) == 'table' then Registry.removeEntities(netIds) end
    end)
end
