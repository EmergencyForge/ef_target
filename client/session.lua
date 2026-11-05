-- One targeting session: owns the menu state and keeps the NUI panel in step with the current target.
local Session = {}
EFT.Session = Session

local active, disabled = false, false
local state = { menu = nil, history = {} }
local target, rows, signature, index, shown
-- What the open menu belongs to. Survives hide: a target lost for one scan is not a new target.
local focus
-- Bumped when a session ends, so a click that outlives its session can tell
local sessionId = 0

local function hide()
    if shown then EFT.Nui.hide() end
    target, rows, signature, index, shown = nil, {}, nil, 1, false
end

local function rowKey(row)
    return row.option.name or row.option.label
end

local function pointKey(t)
    return t and t.point and t.point.key
end

local function focusOf(t)
    if t.point then return t.point.key end
    if t.entity and t.entity ~= 0 then return t.entity end
    return t.zones[1] and 'z' .. t.zones[1].id
end

function Session.isActive() return active end
function Session.menu() return state.menu end
-- True while the panel has rows, a target without allowed options does not count
function Session.hasTarget() return target ~= nil end

function Session.blocked()
    if disabled or IsPauseMenuActive() or IsNuiFocused() or IsPedDeadOrDying(PlayerPedId(), true) then return true end
    -- The lib may be stopped or older than this call, so a failing lookup counts as "not busy"
    if exports then
        local ok, busy = pcall(function() return exports.ef_lib:IsProgressBarActive() end)
        if ok and busy then return true end
    end
    -- ox_lib exports its functions, its lib table is not loaded into this resource
    if exports and GetResourceState and GetResourceState('ox_lib') == 'started' then
        local ok, busy = pcall(function() return exports.ox_lib:progressActive() end)
        if ok and busy then return true end
    end
    return false
end

function Session.begin()
    if active or Session.blocked() then return false end
    active = true
    hide()
    return true
end

function Session.stop(reason)
    if not active then return end
    active = false
    sessionId = sessionId + 1
    -- A new table: a click still running keeps writing to the old one
    state, focus = { history = {} }, nil
    EFT.Filter.reset()
    EFT.Nui.hide()
    target, rows, signature, index, shown = nil, {}, nil, 1, false
end

function Session.disable(value)
    disabled = value and true or false
    if disabled then Session.stop('disabled') end
end

function Session.update(newTarget)
    if not active then return end
    if Session.blocked() then return Session.stop('blocked') end
    if not newTarget then return hide() end

    -- A submenu has no rows on anything else, only its back row would be left
    local newFocus = focusOf(newTarget)
    if newFocus ~= focus then
        focus = newFocus
        state.menu, state.history = nil, {}
    end

    local newRows, title = EFT.Menu.build(newTarget, state)
    if #newRows == 0 then return hide() end
    local snapped = pointKey(newTarget) and pointKey(target) ~= pointKey(newTarget)
    target = newTarget

    -- Title is part of the key: a point can rename the panel without changing a single row
    local sig = EFT.Menu.signature(newRows) .. '\29' .. (title or '')
    if sig == signature then
        rows = newRows
        -- Split bones of one option give equal rows, the new point still starts at the top
        if snapped and index ~= 1 then
            index = 1
            EFT.Nui.select(index)
        end
        return
    end

    -- The options of a freshly snapped point come preselected, otherwise the selection follows its option
    local wanted = not snapped and rows and rows[index] and rowKey(rows[index])
    local newIndex = 1
    if wanted then
        for i, row in ipairs(newRows) do
            if rowKey(row) == wanted then newIndex = i break end
        end
    end
    rows, signature, index, shown = newRows, sig, newIndex, true
    EFT.Nui.show(rows, title, index)
end

function Session.wheel(delta)
    if not active or not target or #rows == 0 then return end
    index = (index - 1 + delta) % #rows + 1
    EFT.Nui.select(index)
end

function Session.click()
    if not active or not target or not rows[index] then return end
    local current, mine = target, sessionId
    local result = EFT.Select.run(rows[index], current, state)
    if mine ~= sessionId then return end
    if result == 'closed' then
        Session.stop('select')
    elseif result == 'menu' then
        -- A new menu starts at its first row, so the old selection must not carry over
        signature, index = nil, 1
        rows = {}
        Session.update(current)
    else
        hide()
    end
end
