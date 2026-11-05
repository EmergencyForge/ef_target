-- One targeting session: owns the menu state and keeps the NUI panel in step with the current target.
local Session = {}
EFT.Session = Session

local active, disabled = false, false
local state = { menu = nil, history = {} }
local target, rows, signature, index, shown

local function hide()
    if shown then EFT.Nui.hide() end
    target, rows, signature, index, shown = nil, {}, nil, 1, false
end

local function rowKey(row)
    return row.option.name or row.option.label
end

function Session.isActive() return active end

function Session.blocked()
    if disabled or IsPauseMenuActive() or IsNuiFocused() or IsPedDeadOrDying(PlayerPedId(), true) then return true end
    -- The lib may be stopped or older than this call, so a failing lookup counts as "not busy"
    if exports then
        local ok, busy = pcall(function() return exports.ef_lib:IsProgressBarActive() end)
        if ok and busy then return true end
    end
    if lib and lib.progressActive and lib.progressActive() then return true end
    return false
end

function Session.begin()
    if active or Session.blocked() then return false end
    active = true
    state.menu, state.history = nil, {}
    hide()
    return true
end

function Session.stop(reason)
    if not active then return end
    active = false
    state.menu, state.history = nil, {}
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

    local newRows, title = EFT.Menu.build(newTarget, state)
    if #newRows == 0 then return hide() end
    target = newTarget

    -- Title is part of the key: a point can rename the panel without changing a single row
    local sig = EFT.Menu.signature(newRows) .. '\29' .. (title or '')
    if sig == signature then
        rows = newRows
        return
    end

    local wanted = rows and rows[index] and rowKey(rows[index])
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
    local current = target
    local result = EFT.Select.run(rows[index], current, state)
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
