-- show='near' points: visible without a key, the nearest one offers its first option on the use key.
local Near = {}
EFT.Near = Near

local TICK_MS = 500

-- Points in reach with an allowed option, and the nearest of them
local nearby, nearest = {}, nil
-- Text on the pill, nil while the pill is hidden
local pillLabel = nil
local ticking, framing = false, false

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

function Near.tick(playerCoords, now)
    nearby = {}
    if EFT.Session.isActive() or EFT.Session.blocked() then return nil end
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

local function hidePill()
    if pillLabel then
        pillLabel = nil
        EFT.Nui.pillHide()
    end
end

-- Keys without a printable name come back as button icons. Community table, not documented by cfx.re:
-- https://forum.cfx.re/t/help-how-to-get-the-current-keybind-of-a-registered-keymap/1847600/7
local BUTTON_KEYS = {
    [100] = 'M1', [101] = 'M2', [102] = 'M3', [115] = 'Rad auf', [116] = 'Rad ab',
    [130] = 'Num-', [131] = 'Num+', [134] = 'Num*', [135] = 'Enter',
    [194] = '↑', [195] = '↓', [196] = '←', [197] = '→', [198] = 'Entf', [199] = 'Esc', [200] = 'Einfg', [201] = 'Ende',
    [210] = 'Entf', [211] = 'Einfg', [212] = 'Ende', [1000] = 'Shift', [1002] = 'Tab', [1003] = 'Enter',
    [1004] = 'Back', [1008] = 'Pos1', [1009] = 'Bild auf', [1010] = 'Bild ab', [1012] = 'Caps', [1013] = 'Strg',
    [1014] = 'Strg', [1015] = 'Alt', [1055] = 'Pos1', [1056] = 'Bild auf', [2000] = 'Leer',
}

local function buttonKey(code)
    if code >= 103 and code <= 110 then return 'M' .. code - 99 end
    if code >= 137 and code <= 145 then return 'Num' .. code - 136 end
    if code >= 170 and code <= 193 then return 'F' .. code - 169 end
    return BUTTON_KEYS[code] and L(BUTTON_KEYS[code]) or '?'
end

-- The player can rebind the key in the game settings, the config only holds its default
function Near.useKey()
    local button = GetControlInstructionalButton(0, joaat('+ef_target_use') | 0x80000000, true)
    if not button then return Config.UseKey end
    local code = button:match('^b_(%d+)$')
    if code then return buttonKey(tonumber(code)) end
    return button:match('^t_(.+)$') or Config.UseKey
end

local function pillFrames()
    while nearest do
        local point = nearest
        -- Written back so the marker of a moving vehicle stays under the pill
        point.coords = EFT.Points.resolve(point.entries[1], point.entity) or point.coords
        local c = point.coords
        local onScreen, x, y = GetScreenCoordFromWorldCoord(c.x, c.y, c.z)
        if onScreen then
            EFT.Nui.pillPos(x, y)
            local label = point.option.label or ''
            if pillLabel ~= label then
                pillLabel = label
                EFT.Nui.pill(Near.useKey(), label, EFT.Menu.holdTime(point.option))
            end
        else
            hidePill()
        end
        Wait(0)
    end
    framing = false
end

-- Runs the check now and applies it to the markers and the pill. A running session owns the renderer.
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

    if not nearest then
        hidePill()
    elseif not framing then
        framing = true
        CreateThread(pillFrames)
    end
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
    local point = Near.tick(GetEntityCoords(PlayerPedId()), GetGameTimer())
    if not point then return end
    -- A use key press has no session: the row context comes from the point alone and a submenu has nowhere to open
    EFT.Select.run({ option = point.option, entry = point.entry, point = point }, {}, { history = {} })
end
