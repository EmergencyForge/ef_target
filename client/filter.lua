EFT.Filter = {}
local Filter = EFT.Filter

local INTERACT_MS = 250
-- Weak keys so options dropped by the registry take their answers with them
local cache = setmetatable({}, { __mode = 'k' })

function Filter.static(option, distance, menu)
    if option.menuName ~= menu then return false end
    if distance > (option.distance or Config.DefaultDistance) then return false end
    if option.groups and not EFT.Framework.hasGroup(option.groups) then return false end
    if option.items and not EFT.Framework.hasItems(option.items, option.anyItem) then return false end
    if option.guard and not option.guard() then return false end
    return true
end

function Filter.force(option, ctx)
    if not option.canInteract then return true end
    local ok, result
    if option.qbInteract then
        ok, result = pcall(option.canInteract, ctx.entity, ctx.distance, option)
    else
        ok, result = pcall(option.canInteract, ctx.entity, ctx.distance, ctx.coords, option.name, ctx.bone)
    end
    return ok and result and true or false
end

function Filter.interact(option, ctx, now)
    if not option.canInteract then return true end
    local hit = cache[option]
    if hit and hit.entity == ctx.entity and now - hit.at < INTERACT_MS then return hit.result end
    local result = Filter.force(option, ctx)
    cache[option] = { entity = ctx.entity, at = now, result = result }
    return result
end

function Filter.reset()
    cache = setmetatable({}, { __mode = 'k' })
end
