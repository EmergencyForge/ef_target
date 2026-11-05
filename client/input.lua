-- Keys and per-frame controls of a session. Selection runs on the wheel and left click, there is no NUI focus.
local CONTROLS = { 14, 15, 16, 17, 24, 25, 37, 140, 141, 142 }
local WHEEL_DOWN, WHEEL_UP, CLICK = 14, 15, 24

local looping, clicking = false, false

local function click()
    EFT.Session.click()
    clicking = false
end

-- The session can end on its own, through a blocker or a finished option, so the cleanup hangs on this loop and not on the key
local function frames()
    local Session = EFT.Session
    local player = PlayerId()
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
    looping = false
    EFT.Scan.stop()
    EFT.Render.setAim(nil)
    EFT.Render.stop()
    EFT.Nui.pillHide()
    EFT.Near.sync()
end

local function start()
    if not EFT.Session.begin() then return end
    -- An error inside a click must not leave the button dead for good
    clicking = false
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
