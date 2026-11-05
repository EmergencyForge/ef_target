-- Turns a target into panel rows. Pure data: no NUI, no natives, so the same rows can be diffed by signature.
local Menu = {}
EFT.Menu = Menu

local titles = { [1] = 'Person', [2] = 'Fahrzeug', [3] = 'Objekt' }

-- Point rows come first, then the general entries of the entity, then zones
function Menu.build(target, state)
    local rows = {}
    local now = GetGameTimer()

    if state.menu then
        local back = { name = 'builtin:goback', label = L('Zurück'), icon = 'fa-solid fa-circle-chevron-left' }
        rows[1] = { id = back.name, label = back.label, icon = back.icon, divider = false, option = back }
    end

    local function add(entry, id, options, ctx, distance, extra)
        for index, option in ipairs(options) do
            if EFT.Filter.static(option, distance, state.menu) and EFT.Filter.interact(option, ctx, now) then
                local row = { id = id .. ':' .. index, label = option.label, icon = option.icon, iconColor = option.iconColor,
                    divider = false, option = option, entry = entry }
                for k, v in pairs(extra or {}) do row[k] = v end
                rows[#rows + 1] = row
            end
        end
    end

    local point = target.point
    if point then
        for _, entry in ipairs(point.entries) do
            local ctx = { entity = point.entity, distance = point.distance, coords = point.coords, bone = entry.anchor and entry.anchor.bone }
            add(entry, entry.id, entry.options, ctx, point.distance, { point = point })
        end
    end
    local pointRows = #rows

    local ctx = { entity = target.entity, distance = target.distance, coords = target.coords }
    for _, entry in ipairs(target.entries) do
        add(entry, entry.id, entry.options, ctx, entry.unlimited and 0 or target.distance)
    end
    for _, zone in ipairs(target.zones) do
        add(zone, 'z' .. zone.id, zone.options, ctx, target.distance, { zone = zone.id })
    end

    if point and rows[pointRows + 1] then rows[pointRows + 1].divider = true end

    local title = point and point.label
    if not title and target.entity and target.entity ~= 0 and titles[target.entityType] then title = L(titles[target.entityType]) end
    if not title and target.zones[1] then title = target.zones[1].label end
    return rows, title
end

-- Equal while the NUI needs nothing new, so callbacks and distances never trigger a repaint
function Menu.signature(rows)
    local parts = {}
    for i, row in ipairs(rows) do
        parts[i] = table.concat({ row.id, row.label or '', row.icon or '', row.iconColor or '', row.divider and 'd' or '' }, '\31')
    end
    return table.concat(parts, '\30')
end
