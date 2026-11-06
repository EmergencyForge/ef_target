-- Fixed points on entities and world coordinates: resolve anchors, merge, pick, snap and refresh visibility.
local Points = {}
EFT.Points = Points

local SNAP_HOLD = 0.7

local MERGE_DISTANCE = 0.4
-- Round robin position for refresh, one point per call keeps the cross-resource filter calls spread out
local cursor = 0

-- Skeleton and size belong to the model, so the lookups by name only have to happen once
local boneIndexes, modelSizes = {}, {}

local function boneIndex(anchor, entity, model)
    local indexes = boneIndexes[model]
    if not indexes then
        indexes = {}
        boneIndexes[model] = indexes
    end
    local index = indexes[anchor]
    if index then return index end
    index = GetEntityBoneIndexByName(entity, anchor.bone)
    if index == -1 and anchor.fallback then index = GetEntityBoneIndexByName(entity, anchor.fallback) end
    -- A deleted entity also answers -1, which says nothing about its model
    if index ~= -1 or DoesEntityExist(entity) then indexes[anchor] = index end
    return index
end

local function modelSize(model)
    local size = modelSizes[model]
    if not size then
        local min, max = GetModelDimensions(model)
        size = { min = min, extent = max - min }
        modelSizes[model] = size
    end
    return size
end

-- Returns the world position of an entry's anchor, nil when the bone does not exist.
-- model saves a native where the caller already knows it.
function Points.resolve(entry, entity, model)
    local anchor = entry.anchor
    if anchor.coords then return anchor.coords end
    if anchor.bone then
        local index = boneIndex(anchor, entity, model or GetEntityModel(entity))
        if index == -1 then return nil end
        return GetEntityBonePosition_2(entity, index)
    end
    local offset = anchor.offset
    if anchor.relative then
        local size = modelSize(model or GetEntityModel(entity))
        offset = size.extent * offset + size.min
    end
    return GetOffsetFromEntityInWorldCoords(entity, offset.x, offset.y, offset.z)
end

local function keyOf(anchor, entity)
    if anchor.bone then return entity .. ':b:' .. anchor.bone end
    local v = anchor.coords
    if v then return 'c:' .. v.x .. ',' .. v.y .. ',' .. v.z end
    v = anchor.offset
    return entity .. ':o:' .. v.x .. ',' .. v.y .. ',' .. v.z
end

-- Entries from one split option sit within 0.4 m of each other when the option has several bones
local function mergesInto(points, entry, coords)
    if not entry.source then return false end
    for _, point in ipairs(points) do
        for _, other in ipairs(point.entries) do
            if other.source == entry.source and #(point.coords - coords) < MERGE_DISTANCE then return true end
        end
    end
    return false
end

function Points.collect(entity, entries, playerCoords, model)
    local points, byKey = {}, {}
    for _, entry in ipairs(entries) do
        if entry.anchor then
            local coords = Points.resolve(entry, entity, model)
            if coords then
                local key = keyOf(entry.anchor, entity)
                local point = byKey[key]
                if point then
                    point.entries[#point.entries + 1] = entry
                elseif not mergesInto(points, entry, coords) then
                    point = {
                        key = key, coords = coords, label = entry.label, icon = entry.icon, entries = { entry },
                        show = entry.show, entity = entity, model = model,
                        distance = #(coords - playerCoords),
                    }
                    byKey[key] = point
                    points[#points + 1] = point
                end
            end
        end
    end
    return points
end

function Points.pick(points, max)
    local sorted = {}
    for i, point in ipairs(points) do sorted[i] = point end
    table.sort(sorted, function(a, b) return a.distance < b.distance end)
    for i = #sorted, max + 1, -1 do sorted[i] = nil end
    return sorted
end

-- Distance is in screen heights so the snap zone is a circle on any aspect ratio
-- heldKey counts as closer than it is, a cursor resting on the edge of the radius must not flip between targets
function Points.snap(points, radius, aspect, heldKey)
    local best, bestDist = nil, radius
    for _, point in ipairs(points) do
        if point.visible and not point.noSnap and point.sx then
            local dx, dy = (point.sx - 0.5) * aspect, point.sy - 0.5
            local dist = math.sqrt(dx * dx + dy * dy)
            if heldKey and point.key == heldKey then dist = dist * SNAP_HOLD end
            if dist < bestDist then best, bestDist = point, dist end
        end
    end
    return best
end

-- A point nobody has checked yet goes ahead of the round robin, visible stays nil until then
local function nextToCheck(points)
    for _, point in ipairs(points) do
        if point.visible == nil then return point end
    end
    cursor = cursor % #points + 1
    return points[cursor]
end

function Points.refresh(points, ctx, now)
    if #points == 0 then return end
    local point = nextToCheck(points)
    local distance = #(ctx.playerCoords - point.coords)
    local visible = false
    for _, entry in ipairs(point.entries) do
        local optionCtx = { entity = point.entity, distance = distance, coords = point.coords, bone = entry.anchor.bone }
        for _, option in ipairs(entry.options) do
            if EFT.Filter.static(option, distance, ctx.menu) and EFT.Filter.interact(option, optionCtx, now) then
                visible = true
                break
            end
        end
        if visible then break end
    end
    point.visible = visible
end

