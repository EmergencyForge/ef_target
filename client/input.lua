-- Keys and per-frame controls of a session. Selection runs on the wheel, left click and the use key, there is no NUI focus.
-- 38 and 86 sit on E by default, the use key must not pick up or honk during a session
local CONTROLS = { 14, 15, 16, 17, 24, 25, 37, 38, 86, 140, 141, 142 }
local FIRE_CONTROLS = { 24, 140, 141, 142 }
local WHEEL_DOWN, WHEEL_UP, CLICK, BACK = 14, 15, 24, 25

local looping, clicking = false, false
-- Read here instead of in the hold loop: a disabled control only reports after this frame disabled it
local mouseDown, useDown = false, false

-- True once the key stayed down on the same entry for the whole time
local function held(ms, selected)
    local wanted = selected()
    local deadline = GetGameTimer() + ms
    EFT.Nui.hold(ms)
    while GetGameTimer() < deadline do
        Wait(0)
        if not (mouseDown or useDown) or selected() ~= wanted then
            EFT.Nui.hold(0)
            return false
        end
    end
    EFT.Nui.hold(0)
    return true
end

-- On its own thread: run may block for a whole progress bar and the frame loop has to keep going meanwhile
local function press(holdTime, selected, run)
    if clicking then return end
    clicking = true
    CreateThread(function()
        local ok, err = pcall(function()
            local ms = holdTime()
            if not ms or held(ms, selected) then run() end
        end)
        clicking = false
        if not ok then print('[ef_target] click failed: ' .. tostring(err)) end
    end)
end

local function sessionFrames(player)
    local Session = EFT.Session
    while Session.isActive() do
        DisablePlayerFiring(player, true)
        for _, control in ipairs(CONTROLS) do DisableControlAction(0, control, true) end
        mouseDown = IsDisabledControlPressed(0, CLICK)
        if IsDisabledControlJustPressed(0, WHEEL_DOWN) then Session.wheel(1) end
        if IsDisabledControlJustPressed(0, WHEEL_UP) then Session.wheel(-1) end
        if IsDisabledControlJustPressed(0, BACK) then Session.back() end
        if IsDisabledControlJustPressed(0, CLICK) then press(Session.holdTime, Session.selected, Session.click) end
        Wait(0)
    end
    mouseDown = false
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
    -- Sent per session, the player can rebind the key at any time
    EFT.Nui.key(EFT.Near.useKey())
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

RegisterCommand('+ef_target_use', function()
    useDown = true
    local Session, Near = EFT.Session, EFT.Near
    if Session.isActive() then
        press(Session.holdTime, Session.selected, Session.click)
    else
        press(Near.holdTime, Near.selected, Near.use)
    end
end, false)

RegisterCommand('-ef_target_use', function() useDown = false end, false)

RegisterKeyMapping('+ef_target', L('Zielen'), 'keyboard', Config.Key)
RegisterKeyMapping('+ef_target_use', L('Interagieren'), 'keyboard', Config.UseKey)
