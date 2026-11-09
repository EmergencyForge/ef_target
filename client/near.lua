-- show='near' points: visible without a key, the nearest one offers its first option on the use key
-- and shows it as a one row menu.
local Near = {}
EFT.Near = Near

local TICK_MS = 500

-- Points in reach with an allowed option, and the nearest of them
local nearby, nearest = {}, nil
-- Point key and option the menu shows, nil while it is hidden
local shown, shownOption = nil, nil
local ticking = false

-- The use key has no panel, so an option that only opens a submenu has nothing to run
local function usable(option)
    return not option.openMenu or option.onSelect or option.export or option.event or option.serverEvent or option.command
end

local function firstAllowed(point, now)
    for _, entry in ipairs(point.entries) do
        local ctx = EFT.Menu.context({ point = point, entry = entry })
        for _, option in ipairs(entry.options) do
            if usable(option) and EFT.Filter.static(option, point.distance, nil) and EFT.Filter.interact(option, ctx, now) then
                return option, entry
            end
        end
    end
end

function Near.tick(playerCoords, now, fresh)
    nearby = {}
    if EFT.Session.isActive() or EFT.Session.blocked(fresh) then return nil end
    if GetVehiclePedIsIn(PlayerPedId(), false) ~= 0 then return nil end

    local Scan = EFT.Scan
    local best = nil
    local entities = Scan.pointEntities(EFT.Registry.nearPools(), 'near', playerCoords)
    -- Only near entries go in, so a point shared with alt entries still counts and never offers those on the use key
    for _, point in ipairs(Scan.collectPoints(entities, 'near', playerCoords)) do
        point.option, point.entry = firstAllowed(point, now)
        if point.option then
            nearby[#nearby + 1] = point
            if not best or point.distance < best.distance then best = point end
        end
    end
    return best
end

local function hideMenu()
    if shown then
        shown, shownOption = nil, nil
        EFT.Nui.hide()
    end
end

-- The point gets its own menu only when it or its option changes, a moving vehicle is followed by Surface
local function showMenu(point)
    local option = point.option
    if shown == point.key and shownOption == option then return end
    shown, shownOption = point.key, option
    EFT.Surface.place(point.coords, nil, point.entity)
    EFT.Nui.show({ { id = 'near', label = option.label, icon = option.icon, iconColor = option.iconColor } }, 1)
end

-- Runs the check now and applies it to the markers and the menu. A running session owns the renderer.
function Near.sync()
    nearest = Near.tick(GetEntityCoords(PlayerPedId()), GetGameTimer())

    if not EFT.Session.isActive() then
        local Render = EFT.Render
        if #nearby > 0 then
            if not Render.isRunning() then Render.start() end
            Render.setPoints(nearby)
            EFT.Scan.adopt(nearby)
        elseif Render.isRunning() then
            Render.stop()
        end
    end

    if nearest then showMenu(nearest) else hideMenu() end
end

local function anyNearPoints()
    for _, on in pairs(EFT.Registry.nearPools()) do
        if on then return true end
    end
    return false
end

local reported = {}

-- An error in one tick must not end the thread, or ticking stays true and no later near point ever starts another
local function safeSync()
    local ok, err = pcall(Near.sync)
    if ok then return end
    -- error(nil) is legal and nil cannot index a table
    err = tostring(err)
    if not reported[err] then
        reported[err] = true
        print(('[ef_target] near check failed: %s'):format(err))
    end
end

EFT.Registry.onNearAdded = function()
    if ticking then return end
    ticking = true
    CreateThread(function()
        while anyNearPoints() do
            safeSync()
            Wait(TICK_MS)
        end
        safeSync()
        ticking = false
    end)
end

function Near.selected()
    return nearest and nearest.option
end

function Near.holdTime()
    local option = Near.selected()
    return option and EFT.Menu.holdTime(option)
end

function Near.use()
    local point = Near.tick(GetEntityCoords(PlayerPedId()), GetGameTimer(), true)
    if not point then return end
    -- A use key press has no session: the row context comes from the point alone and a submenu has nowhere to open
    EFT.Select.run({ option = point.option, entry = point.entry, point = point }, {}, { history = {} })
end
