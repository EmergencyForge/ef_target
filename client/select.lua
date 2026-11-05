-- Runs the option a player picked. Every call into foreign code is guarded so one broken option cannot wedge the panel.
local Select = {}
EFT.Select = Select

-- Fields that are internals or already acted upon, the receiving resource does not need them
local dropped = { 'icon', 'iconColor', 'groups', 'items', 'anyItem', 'canInteract', 'onSelect', 'export', 'event', 'serverEvent', 'command', 'source' }

function Select.response(option, target, server, row)
    local response = {}
    for k, v in pairs(option) do response[k] = v end
    for _, key in ipairs(dropped) do response[key] = nil end
    response.entity = server and (target.netId or 0) or target.entity
    local point = row and row.point
    response.coords = point and point.coords or target.coords
    response.distance = point and point.distance or target.distance
    response.zone = row and row.zone or nil
    response.point = point and { key = point.key, coords = point.coords } or nil
    return response
end

local function call(row, option, target)
    local response = Select.response(option, target, false, row)
    if option.onSelect then
        option.onSelect(option.qtarget and target.entity or response)
    elseif option.export then
        exports[option.resource or row.entry.resource][option.export](nil, response)
    elseif option.event then
        TriggerEvent(option.event, response)
    elseif option.serverEvent then
        TriggerServerEvent(option.serverEvent, Select.response(option, target, true, row))
    elseif option.command then
        ExecuteCommand(option.command)
    end
end

function Select.run(row, target, state)
    local option = row.option
    if option.name == 'builtin:goback' then
        local previous = table.remove(state.history)
        state.menu = previous ~= 'home' and previous or nil
        return 'menu'
    end

    local entity = row.point and row.point.entity or target.entity
    if entity and entity ~= 0 and not DoesEntityExist(entity) then return 'stale' end
    if not EFT.Filter.force(option, EFT.Menu.context(row, target)) then return 'stale' end

    local result = 'closed'
    local savedMenu, savedHistory = state.menu, #state.history
    if option.openMenu then
        -- nil cannot live in an array, so the home menu is stored as 'home'
        state.history[#state.history + 1] = state.menu or 'home'
        state.menu = option.openMenu ~= 'home' and option.openMenu or nil
        result = 'menu'
    end
    local ok, err = pcall(call, row, option, target)
    if not ok then
        print(('[ef_target] option %s failed: %s'):format(option.name or option.label or '?', tostring(err)))
        for i = #state.history, savedHistory + 1, -1 do state.history[i] = nil end
        state.menu = savedMenu
        return 'closed'
    end
    return result
end
