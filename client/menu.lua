-- Turns a target into panel rows. Pure data: no NUI, no natives, so the same rows can be diffed by signature.
local Menu = {}
EFT.Menu = Menu

local titles = { [1] = 'Person', [2] = 'Fahrzeug', [3] = 'Objekt' }

-- One context for showing and running a row, so a visible option cannot go stale on click
function Menu.context(row, target)
    local point = row.point
    if point then
        return { entity = point.entity, distance = point.distance, coords = point.coords,
            bone = row.entry and row.entry.anchor and row.entry.anchor.bone }
    end
    return { entity = target.entity, distance = target.distance, coords = target.coords }
end

-- Milliseconds the key has to stay down, nil runs the option on the press
function Menu.holdTime(option)
    local hold = option.hold
    if type(hold) == 'number' and hold > 0 then return hold end
end

-- Point rows come first, then the general entries of the entity, then zones
function Menu.build(target, state)
    local rows = {}
    local now = GetGameTimer()

    -- Runs every scan over every option of the target, most of them never become a row
    local function add(entry, id, options, distance, point, zone)
        local ctx = Menu.context({ point = point, entry = entry }, target)
        for index, option in ipairs(options) do
            if EFT.Filter.static(option, distance, state.menu) and EFT.Filter.interact(option, ctx, now) then
                rows[#rows + 1] = { id = id .. ':' .. index, label = option.label, icon = option.icon, iconColor = option.iconColor,
                    divider = false, option = option, entry = entry, hold = Menu.holdTime(option),
                    submenu = option.openMenu ~= nil, point = point, zone = zone }
            end
        end
    end

    local point = target.point
    if point then
        for _, entry in ipairs(point.entries) do
            add(entry, entry.id, entry.options, point.distance, point)
        end
    end
    local pointRows = #rows

    for _, entry in ipairs(target.entries) do
        add(entry, entry.id, entry.options, entry.unlimited and 0 or target.distance)
    end
    for _, zone in ipairs(target.zones) do
        add(zone, 'z' .. zone.id, zone.options, target.distance, nil, zone.id)
    end

    if pointRows > 0 and rows[pointRows + 1] then rows[pointRows + 1].divider = true end

    local title = point and point.label
    if not title and target.entity and target.entity ~= 0 and titles[target.entityType] then title = L(titles[target.entityType]) end
    if not title and target.zones[1] then title = target.zones[1].label end
    return rows, title
end

-- Equal while the NUI needs nothing new, so callbacks and distances never trigger a repaint
function Menu.signature(rows)
    local parts = {}
    for i, row in ipairs(rows) do
        parts[i] = table.concat({ row.id, row.label or '', row.icon or '', row.iconColor or '', row.divider and 'd' or '',
            row.hold or '', row.submenu and 's' or '' }, '\31')
    end
    return table.concat(parts, '\30')
end
