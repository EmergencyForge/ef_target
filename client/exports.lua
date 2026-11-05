-- The public API. Everything a caller adds carries its resource name, so it leaves when that resource stops.
local Compat = EFT.Compat
local Registry = EFT.Registry
local caller = Compat.caller

local function anchorOf(data)
    if data.bone then return { bone = data.bone } end
    -- Metres from the entity, unlike the 0 to 1 fractions of foreign offset options
    if data.offset then return { offset = data.offset } end
    error('target point needs a bone or an offset', 3)
end

local function addPoint(data)
    local resource = caller()
    local options = Registry.normalize(data.options)
    for _, option in ipairs(options) do option.distance = option.distance or data.distance end

    local extra = { show = data.show, label = data.label }
    if data.coords then
        extra.anchor = { coords = data.coords }
        return Registry.add('point', 'coords', options, resource, extra)
    end
    if not (data.global or data.model or data.entity) then
        error('target point needs global, model, entity or coords', 2)
    end
    extra.anchor = anchorOf(data)
    if data.global then return Registry.add('global', data.global, options, resource, extra) end
    if data.model then return Compat.addModels(data.model, options, resource, extra) end
    return Registry.addEntity(data.entity, options, resource, extra)
end

-- Fixing the type turns a box without a size into an error, the inference would make it a sphere
local function zoneAdder(kind)
    return function(data)
        data.type = kind
        return Registry.addZone(data, caller())
    end
end

exports('AddPoint', addPoint)
exports('AddGlobal', function(kind, options) return Registry.add('global', kind, options, caller()) end)
exports('AddModel', function(models, options) return Compat.addModels(models, options, caller()) end)
exports('AddEntity', function(entity, options) return Registry.addEntity(entity, options, caller()) end)
exports('AddBoxZone', zoneAdder('box'))
exports('AddSphereZone', zoneAdder('sphere'))
exports('AddPolyZone', zoneAdder('poly'))
exports('Remove', function(id)
    Registry.remove(id)
    Registry.removeZone(id)
end)
exports('DisableTargeting', function(state) EFT.Session.disable(state) end)
exports('IsActive', function() return EFT.Session.isActive() end)
