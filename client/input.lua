-- Keys and per-frame controls of a session. Selection runs on the wheel and left click, there is no NUI focus.
local CONTROLS = { 14, 15, 16, 17, 24, 25, 37, 140, 141, 142 }
local FIRE_CONTROLS = { 24, 140, 141, 142 }
local WHEEL_DOWN, WHEEL_UP, CLICK = 14, 15, 24

local looping, clicking = false, false

local function click()
    local ok, err = pcall(EFT.Session.click)
    clicking = false
    if not ok then print('[ef_target] click failed: ' .. tostring(err)) end
end

local function sessionFrames(player)
    local Session = EFT.Session
    while Session.isActive() do
        DisablePlayerFiring(player, true)
        for _, control in ipairs(CONTROLS) do DisableControlAction(0, control, true) end
        if IsDisabledControlJustPressed(0, WHEEL_DOWN) then Session.wheel(1) end
        if IsDisabledControlJustPressed(0, WHEEL_UP) then Session.wheel(-1) end
        -- onSelect may block for a whole progress bar, this loop has to keep going meanwhile
        if IsDisabledControlJustPressed(0, CLICK) and not clicking then
            clicking = true
            CreateThread(click)
        end
        Wait(0)
    end
end

-- The button is usually still down when a click ends the session, freed controls would fire the drawn weapon.
-- Disabling comes first, the pressed state of an enabled control reads as false.
local function holdFire(player)
    while not EFT.Session.isActive() do
        DisablePlayerFiring(player, true)
        for _, control in ipairs(FIRE_CONTROLS) do DisableControlAction(0, control, true) end
        if not IsDisabledControlPressed(0, CLICK) then return end
        Wait(0)
    end
end

-- The session can end on its own, through a blocker or a finished option, so the cleanup hangs on this loop and not on the key.
-- A press during the hold finds looping set and comes back in here through the repeat.
local function frames()
    local player = PlayerId()
    repeat
        sessionFrames(player)
        EFT.Scan.stop()
        EFT.Render.setAim(nil)
        EFT.Render.stop()
        EFT.Near.sync()
        holdFire(player)
    until not EFT.Session.isActive()
    looping = false
end

local function start()
    if not EFT.Session.begin() then return end
    EFT.Render.start()
    EFT.Near.sync()
    EFT.Scan.start()
    if not looping then
        looping = true
        CreateThread(frames)
    end
end

-- Only a key press starts a session, so one that ended by itself stays off until the key goes down again
RegisterCommand('+ef_target', function()
    if Config.Toggle and EFT.Session.isActive() then
        EFT.Session.stop('toggled')
    else
        start()
    end
end, false)

RegisterCommand('-ef_target', function()
    if not Config.Toggle then EFT.Session.stop('released') end
end, false)

RegisterCommand('+ef_target_use', function() EFT.Near.use() end, false)
-- A mapped + command needs its - partner, or the key runs into an unknown command on release
RegisterCommand('-ef_target_use', function() end, false)

RegisterKeyMapping('+ef_target', L('Zielen'), 'keyboard', Config.Key)
RegisterKeyMapping('+ef_target_use', L('Interagieren'), 'keyboard', Config.UseKey)
