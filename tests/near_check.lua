-- Scan, input, near points and the built-in vehicle points, wired together over stubbed natives.
-- Threads run as coroutines: pump() resumes each one once, Wait hands control back.
local harness = require('tests.harness')
local check = harness.check
local natives = harness.natives

local stubbed = {}
local function stub(list)
    for name, value in pairs(list) do
        stubbed[#stubbed + 1] = name
        natives[name] = value
    end
end

harness.resetEFT()
_G.Config = { Key = 'LMENU', UseKey = 'E', Toggle = false, SnapRadius = 0.035, MaxPoints = 24, DefaultPoints = true,
    DefaultDistance = 7.0, RayLength = 20.0, Locale = 'de', Reticle = { Thickness = 2.0, CenterDot = true } }
_G.L = function(text) return text end
_G.json = { encode = function(t) return t end }

local ped, vehicle, ownVehicle, stranger, otherPlayer, crate, barrel, invalid = 1, 2000, 2001, 3000, 3001, 4000, 4001, 666
local world = {
    [barrel] = { type = 3, model = 89, coords = vec3(7, 0, 0) },
    [ped] = { type = 1, model = 10, coords = vec3(0, 0, 0) },
    [vehicle] = { type = 2, model = 77, coords = vec3(1, 0, 0), netId = 50 },
    [ownVehicle] = { type = 2, model = 77, coords = vec3(0, 0, 0) },
    [stranger] = { type = 1, model = 11, coords = vec3(4, 0, 0) },
    [otherPlayer] = { type = 1, model = 10, coords = vec3(5, 0, 0), netId = 51, player = true },
    [crate] = { type = 3, model = 88, coords = vec3(6, 0, 0) },
}
local pools = { CVehicle = { vehicle }, CPed = { ped, stranger, otherPlayer }, CObject = { crate, barrel } }
local poolUse = {}
local function poolCalls(name, fn)
    local before = poolUse[name] or 0
    fn()
    return (poolUse[name] or 0) - before
end

local clock, sent, commands, mappings, netEvents, serverEvents = 1000, {}, {}, {}, {}, {}
local threads = {}
local function pump(times)
    for _ = 1, times or 1 do
        clock = clock + 50
        local batch, alive = threads, {}
        threads = {}
        for _, thread in ipairs(batch) do
            assert(coroutine.resume(thread))
            if coroutine.status(thread) ~= 'dead' then alive[#alive + 1] = thread end
        end
        for _, thread in ipairs(threads) do alive[#alive + 1] = thread end
        threads = alive
    end
end

local function last(action)
    for i = #sent, 1, -1 do
        if sent[i].action == action then return sent[i] end
    end
end
local function count(action)
    local n = 0
    for _, message in ipairs(sent) do
        if message.action == action then n = n + 1 end
    end
    return n
end

-- Camera sits at (0, -5, 0) looking down +y. A ray of RayLength reads rays[flags], a shorter one is a sight check.
local camera = vec3(0, -5, 0)
local rays, sightHit, sightRays, handles, sightTargets, longRays = {}, nil, 0, {}, {}, {}
local shapeBlocked = false
local function miss() return { hit = false, entity = 0, coords = vec3(0, 0, 0) } end

local bones = { door_dside_f = vec3(0, 1, 0), hood = vec3(0, 2, 0), far = vec3(0, -1, 0) }
local boneIds, boneById, nextBone = {}, {}, 0
for name, offset in pairs(bones) do
    nextBone = nextBone + 1
    boneIds[name], boneById[nextBone] = nextBone, offset
end

local justPressed, heldDown, disabled, fired, typeCalls = {}, {}, {}, 0, {}
local instructional, buttonArgs = 't_E', nil
local inVehicle, paused, doorValid, lockStatus, doorDamaged, doorAngle = 0, false, true, 1, false, 0.0
local doorCalls, owner, networked = {}, 1, true
local onScreen = true

stub({
    AddEventHandler = function() end,
    CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end,
    Wait = function() coroutine.yield() end,
    GetGameTimer = function() return clock end,
    SendNuiMessage = function(message) sent[#sent + 1] = message end,
    RegisterCommand = function(name, fn) commands[name] = fn end,
    RegisterKeyMapping = function(name, label, device, key) mappings[name] = { label = label, device = device, key = key } end,
    RegisterNetEvent = function(name, fn) netEvents[name] = fn end,
    TriggerServerEvent = function(name, ...) serverEvents[#serverEvents + 1] = { name = name, args = { ... } } end,
    GetCurrentResourceName = function() return 'ef_target' end,

    PlayerPedId = function() return ped end,
    PlayerId = function() return 1 end,
    IsPauseMenuActive = function() return paused end,
    IsNuiFocused = function() return false end,
    IsPedDeadOrDying = function() return false end,
    GetVehiclePedIsIn = function() return inVehicle end,
    DoesEntityExist = function(entity) return world[entity] ~= nil end,
    GetEntityCoords = function(entity) return world[entity].coords end,
    GetEntityType = function(entity)
        if entity == invalid then error('no such entity') end
        typeCalls[entity] = (typeCalls[entity] or 0) + 1
        return world[entity] and world[entity].type or 0
    end,
    GetEntityModel = function(entity) return world[entity].model end,
    IsModelAVehicle = function(model) return model == 77 end,
    IsPedAPlayer = function(entity) return world[entity].player or false end,
    NetworkGetEntityIsNetworked = function(entity) return networked and world[entity].netId ~= nil end,
    NetworkGetNetworkIdFromEntity = function(entity) return world[entity].netId end,
    NetworkDoesNetworkIdExist = function(netId) return netId == 50 end,
    NetworkGetEntityFromNetworkId = function(netId) return netId == 50 and vehicle or 0 end,
    NetworkGetEntityOwner = function() return owner end,
    NetToVeh = function(netId) return netId == 50 and vehicle or 0 end,
    GetGamePool = function(name) poolUse[name] = (poolUse[name] or 0) + 1; return pools[name] end,

    GetEntityBoneIndexByName = function(_, name) return boneIds[name] or -1 end,
    GetEntityBonePosition_2 = function(entity, id) return world[entity].coords + boneById[id] end,
    GetModelDimensions = function() return vec3(-1, -2, 0), vec3(1, 2, 2) end,
    GetOffsetFromEntityInWorldCoords = function(entity, x, y, z) return world[entity].coords + vec3(x, y, z) end,

    GetWorldCoordFromScreenCoord = function() return camera, vec3(0, 1, 0) end,
    GetScreenCoordFromWorldCoord = function(x) return onScreen, 0.5 + x / 10, 0.5 end,
    GetAspectRatio = function() return 16 / 9 end,
    StartShapeTestLosProbe = function(fx, fy, fz, tx, ty, tz, flags)
        local length = #(vec3(tx, ty, tz) - vec3(fx, fy, fz))
        if math.abs(length - Config.RayLength) < 0.001 then
            longRays[flags] = (longRays[flags] or 0) + 1
            handles[#handles + 1] = rays[flags] or miss()
        else
            sightRays = sightRays + 1
            sightTargets[#sightTargets + 1] = vec3(tx, ty, tz)
            handles[#handles + 1] = sightHit or miss()
        end
        return #handles
    end,
    GetShapeTestResultIncludingMaterial = function(handle)
        local ray = handles[handle]
        if ray.pending and ray.pending > 0 then
            ray.pending = ray.pending - 1
            return 1, 0, vec3(0, 0, 0), vec3(0, 0, 0), 0, 0
        end
        if ray.failed then return 0, 0, vec3(0, 0, 0), vec3(0, 0, 0), 0, 0 end
        return 2, ray.hit and 1 or 0, ray.coords, vec3(0, 0, 1), 0, ray.entity
    end,
    HasEntityClearLosToEntity = function() return not shapeBlocked end,

    DisablePlayerFiring = function() fired = fired + 1 end,
    DisableControlAction = function(_, control) disabled[control] = true end,
    IsDisabledControlJustPressed = function(_, control) return justPressed[control] or false end,
    IsDisabledControlPressed = function(_, control) return heldDown[control] or false end,
    joaat = function(name) return #name * 256 end,
    GetControlInstructionalButton = function(pad, hash, flag)
        buttonArgs = { pad, hash, flag }
        return instructional
    end,

    CreateRuntimeTxd = function() return 1 end,
    CreateRuntimeTexture = function() return 1 end,
    SetRuntimeTexturePixel = function() end,
    CommitRuntimeTexture = function() end,
    GetFrameTime = function() return 1 / 60 end,
    SetDrawOrigin = function() end,
    ClearDrawOrigin = function() end,
    DrawSprite = function() end,

    GetIsDoorValid = function() return doorValid end,
    GetVehicleDoorLockStatus = function() return lockStatus end,
    IsVehicleDoorDamaged = function() return doorDamaged end,
    GetVehicleDoorAngleRatio = function() return doorAngle end,
    SetVehicleDoorShut = function(_, door) doorCalls[#doorCalls + 1] = 'shut' .. door end,
    SetVehicleDoorOpen = function(_, door) doorCalls[#doorCalls + 1] = 'open' .. door end,
})

harness.load('client/eft.lua')
harness.load('client/geometry.lua')
harness.load('client/registry.lua')
local groupAllowed = true
EFT.Framework = { hasGroup = function() return groupAllowed end, hasItems = function() return true end }
for _, file in ipairs({ 'filter', 'points', 'menu', 'select', 'nui', 'session', 'accent', 'spring', 'render', 'scan', 'near', 'input' }) do
    harness.load('client/' .. file .. '.lua')
end
pump(1)
local R, N, S, Session, Render = EFT.Registry, EFT.Near, EFT.Scan, EFT.Session, EFT.Render

local aimed, aimHit, aimCalls, drawn, emptySends = nil, nil, 0, nil, 0
local realAim, realPoints = Render.setAim, Render.setPoints
Render.setAim = function(point, hit)
    aimed, aimHit, aimCalls = point, hit, aimCalls + 1
    return realAim(point, hit)
end
Render.setPoints = function(list)
    drawn = list
    if #list == 0 then emptySends = emptySends + 1 end
    return realPoints(list)
end

-- Near: pools, range and the resting states
local origin = vec3(0, 0, 0)
local nearRuns = 0
local nearOption = { name = 'near_door', label = 'Tür öffnen', distance = 2.0, onSelect = function() nearRuns = nearRuns + 1 end }

check('no near points means no pool scan', poolCalls('CVehicle', function() N.tick(origin, 0) end) == 0)
check('no near thread without near points', #threads == 0)
local nearId = R.add('global', 'vehicle', nearOption, 'res', { show = 'near', anchor = { bone = 'door_dside_f' } })
check('a near point starts the thread', #threads == 1)
check('only the pool with near points is scanned', poolCalls('CPed', function() N.tick(origin, 0) end) == 0)
check('a point in range wins', N.tick(origin, 500).key == vehicle .. ':b:door_dside_f')
natives.GetVehiclePedIsIn = function() return 9 end
check('near points rest inside a vehicle', N.tick(origin, 1000) == nil)
natives.GetVehiclePedIsIn = function() return inVehicle end
check('a point out of its distance is not near', N.tick(vec3(10, 0, 0), 1500) == nil)
paused = true
check('near points rest while targeting is blocked', N.tick(origin, 2000) == nil)
paused = false

local closer = R.add('entity', 50, { label = 'Netz', distance = 3.0 }, 'res', { show = 'near', anchor = { bone = 'hood' } })
R.remove(nearId)
check('entity points need no pool', poolCalls('CVehicle', function() check('an entity point is found by netId', N.tick(origin, 2500) ~= nil) end) == 0)
R.remove(closer)
local modelId = R.add('model', 88, { label = 'Kiste', distance = 7.0 }, 'res', { show = 'near', anchor = { offset = vec3(0, 0, 0), relative = false } })
check('a prop model leaves the vehicle pool alone', poolCalls('CVehicle', function() check('a model point is found in the pools', N.tick(origin, 3000) ~= nil) end) == 0)
R.remove(modelId)
pump(2)
check('the near thread ends with the last near point', #threads == 0)

-- A failing sync must not end the thread, nor leave it marked as running
local flaky = R.add('global', 'vehicle', nearOption, 'res', { show = 'near', anchor = { bone = 'door_dside_f' } })
local realSync, syncCalls, printed, realPrint = N.sync, 0, {}, print
N.sync = function() syncCalls = syncCalls + 1; error('boom') end
_G.print = function(...) printed[#printed + 1] = table.concat({ ... }, ' ') end
pump(5)
_G.print = realPrint
check('a throwing sync does not stop later ticks', syncCalls >= 4 and #threads == 1)
check('one failure kind prints once', #printed == 1)
N.sync = realSync
R.remove(flaky)
pump(2)
check('the thread ends after failures too', #threads == 0)
flaky = R.add('global', 'vehicle', nearOption, 'res', { show = 'near', anchor = { bone = 'door_dside_f' } })
check('a new near point starts a thread again', #threads == 1)
R.remove(flaky)
pump(2)
threads = {}

-- Near: which entry and option speak for a point
local altFirst = R.add('global', 'vehicle', { label = 'Alt' }, 'res', { anchor = { bone = 'door_dside_f' } })
nearId = R.add('global', 'vehicle', nearOption, 'res', { show = 'near', anchor = { bone = 'door_dside_f' } })
local joined = N.tick(origin, 3500)
check('a near entry behind an alt entry still counts', joined ~= nil and joined.option == nearOption)

local allowed = false
local guarded = { name = 'guarded', label = 'Geschützt', canInteract = function() return allowed end, onSelect = function() nearRuns = nearRuns + 10 end }
local spot = R.add('point', 'coords', { guarded, { label = 'Offen', onSelect = function() nearRuns = nearRuns + 100 end } }, 'res',
    { show = 'near', anchor = { coords = vec3(0.1, 0, 0) } })
check('the nearest point takes the pill', N.tick(origin, 4000).key == 'c:0.1,0,0')
check('the first allowed option speaks for the point', N.tick(origin, 4500).option.label == 'Offen')
N.use()
check('use runs the first allowed option', nearRuns == 100)

local submenuFirst = R.add('point', 'coords', { { label = 'Menü', openMenu = 'm' }, { label = 'Direkt', onSelect = function() end } }, 'res',
    { show = 'near', anchor = { coords = vec3(0.05, 0, 0) } })
check('the pill skips an option the use key cannot do', N.tick(origin, 4600).option.label == 'Direkt')
R.remove(submenuFirst)

threads = {}
sent = {}
N.sync()
check('near points are drawn without the key', drawn and #drawn == 2 and Render.isRunning())
pump(1)
check('the pill shows the option text', last('pill') and last('pill').label == 'Offen' and last('pill').key == 'E')
check('the pill follows the point in screen fractions', last('pillPos') and last('pillPos').x == 0.51 and last('pillPos').y == 0.5)
local position, pills = count('pillPos'), count('pill')
pump(1)
check('the position goes out every frame, the pill once', count('pillPos') == position + 1 and count('pill') == pills)
onScreen = false
pump(1)
check('an off screen point hides the pill', count('pillHide') == 1)
onScreen = true
pump(1)
check('the pill comes back on screen', count('pill') == pills + 1)
commands['+ef_target']()
check('a session takes the pill over', count('pillHide') == 2 and Session.isActive())
commands['-ef_target']()
pump(2)
check('near markers come back when the session ends', Render.isRunning() and #drawn == 2)
pump(1)
check('the pill comes back when the session ends', count('pill') == pills + 2)
R.remove(spot); R.remove(nearId); R.remove(altFirst)
N.sync()
check('no near point left hides the pill', count('pillHide') == 3)
check('no near point left stops the markers', not Render.isRunning())
pump(2)
threads = {}

-- The pill names the key the player really bound
local function pillKeyFor(label)
    instructional = label
    local id = R.add('point', 'coords', { label = 'Drücken' }, 'res', { show = 'near', anchor = { coords = vec3(0.1, 0, 0) } })
    N.sync()
    pump(1)
    local key = last('pill').key
    R.remove(id)
    N.sync()
    pump(1)
    threads = {}
    return key
end
check('the pill reads the rebound key', pillKeyFor('t_G') == 'G')
check('the lookup uses the mapped command', mappings['+ef_target_use'] and buttonArgs and buttonArgs[1] == 0
    and buttonArgs[2] == (joaat('+ef_target_use') | 0x80000000) and buttonArgs[3] == true)
check('a button without text falls back to the config key', pillKeyFor('b_116') == 'E')
check('no answer falls back to the config key', pillKeyFor(nil) == 'E')
instructional = 't_E'

-- Classify
check('the own vehicle is no target', (function()
    natives.GetVehiclePedIsIn = function() return ownVehicle end
    local result = S.classify(ownVehicle)
    natives.GetVehiclePedIsIn = function() return inVehicle end
    return result == nil
end)())
check('the player is no target', S.classify(ped) == nil)
check('a stale handle is no target', S.classify(invalid) == nil)
check('nothing is no target', S.classify(0) == nil)
local kind, model, netId, isPlayer = S.classify(vehicle)
check('a vehicle classifies', kind == 2 and model == 77 and netId == 50 and isPlayer == false)
kind, model, netId, isPlayer = S.classify(otherPlayer)
check('a player classifies', kind == 1 and netId == 51 and isPlayer == true)
kind, model, netId = S.classify(crate)
check('a local entity has no netId', kind == 3 and netId == nil)

-- Key mapping
check('the aim key is mapped', mappings['+ef_target'].key == 'LMENU' and mappings['+ef_target'].label == 'Zielen')
check('the use key is mapped', mappings['+ef_target_use'].key == 'E')

local function press() commands['+ef_target']() end
local function release() commands['-ef_target']() end
local function ray(flags, entity, coords) rays[flags] = { hit = true, entity = entity, coords = coords } end
-- One scan spends a frame on each of up to three rays and one in its pacing Wait
local function scans(times) pump(4 * times) end
local aimsBefore

-- Scan: target from the rays
local general = R.add('global', 'vehicle', { name = 'general', label = 'Durchsuchen' }, 'res')
sent = {}
ray(511, vehicle, vec3(1, 0, 0))
press()
check('the key starts a session', Session.isActive() and Render.isRunning())
scans(2)
check('a hit entity is the target', S.current() and S.current().entity == vehicle and S.current().entityType == 2 and S.current().netId == 50)
check('the panel shows', last('show') and last('show').rows[1].label == 'Durchsuchen')
check('a hit fills the centre marker', aimed and aimed.coords == nil and aimHit == true)
check('the target carries the hit distance', S.current().distance == 1)

ray(511, 0, vec3(0, 3, 0))
ray(26, stranger, vec3(0, 1, 0))
local strangerRow = R.add('global', 'ped', { label = 'Ansprechen' }, 'res')
scans(2)
check('the second ray finds an entity', S.current() and S.current().entity == stranger)
shapeBlocked = true
scans(2)
check('an entity behind cover does not count', S.current() == nil or S.current().entity == nil)
check('no options means an empty marker', aimed ~= nil and aimHit == false)
shapeBlocked = false
ray(26, stranger, vec3(0, 9, 0))
scans(2)
check('the nearer hit counts', S.current() == nil or S.current().entity == nil)
-- Both hits lie on the camera ray, the second is the nearer one from there and the farther one from the player
ray(511, 0, vec3(0, 2, 0))
ray(26, stranger, vec3(0, -4, 0))
scans(2)
check('nearer is measured from the camera', S.current() and S.current().entity == stranger)
rays[511] = { hit = true, entity = vehicle, coords = vec3(1, 0, 0), pending = 1 }
rays[26] = nil
aimsBefore, longRays[26] = aimCalls, 0
repeat pump(1) until aimCalls > aimsBefore + 1
check('a pending ray is read again', S.current() and S.current().entity == vehicle)
check('a pending ray is not taken for a miss', longRays[26] <= 1)
rays[511] = { failed = true }
scans(2)
check('a failed ray reads as a miss', S.current() == nil)
rays[511], rays[26] = nil, nil
scans(2)
check('a miss has no target', S.current() == nil and count('hide') >= 1)
R.remove(strangerRow)

-- Scan: points
ray(511, vehicle, vec3(1, 0, 0))
local doorRun = 0
local door = R.add('global', 'vehicle', { name = 'door', label = 'Tür', distance = 5.0, onSelect = function() doorRun = doorRun + 1 end }, 'res',
    { label = 'Fahrertür', anchor = { bone = 'door_dside_f' } })
local hood = R.add('global', 'vehicle', { name = 'hood', label = 'Haube', distance = 5.0 }, 'res', { anchor = { bone = 'hood' } })
local denied = R.add('global', 'vehicle', { name = 'no', label = 'Nein', canInteract = function() return false end }, 'res', { anchor = { bone = 'far' } })
sightRays = 0
aimsBefore = aimCalls
repeat pump(1) until aimCalls > aimsBefore
check('a new point waits for its first check', #drawn == 0)
aimsBefore, sightRays = aimCalls, 0
scans(6)
check('a scan runs one sight ray at most', sightRays > 0 and sightRays <= aimCalls - aimsBefore)
scans(6)
check('checked points are drawn', #drawn == 2)
check('a point without an allowed option stays hidden', not (drawn[1].entries[1].options[1].name == 'no' or drawn[2].entries[1].options[1].name == 'no'))
check('points live in the panel only when snapped', last('show').rows[1].label == 'Durchsuchen')

-- The fake screen puts x = 1 outside the snap radius and x = 0.1 inside
world[vehicle].coords = vec3(0.1, 0, 0)
scans(1)
check('the aim snaps to the point', aimed and aimed.key == vehicle .. ':b:door_dside_f' and aimHit == true)
check('the point leads the panel', last('show').rows[1].label == 'Tür' and last('show').title == 'Fahrertür')
check('general options stay below a divider', last('show').rows[#last('show').rows].label == 'Durchsuchen' and last('show').rows[#last('show').rows].divider)
check('the points list holds the snapped point', S.current().point.key == aimed.key)

-- Only the point hits, the ray goes past the vehicle
rays[511] = nil
scans(1)
check('a snap without a hit still targets the point entity', S.current() and S.current().entity == vehicle and S.current().point ~= nil)
check('its general options stay reachable', last('show').rows[#last('show').rows].label == 'Durchsuchen')
ray(511, vehicle, vec3(1, 0, 0))

world[ped].coords = vec3(0, 0, 3)
scans(1)
local expected = #(world[vehicle].coords + bones.door_dside_f - world[ped].coords)
check('the point distance stays fresh', math.abs(S.current().point.distance - expected) < 1e-9)
world[ped].coords = vec3(0, 0, 0)

sightHit = { hit = true, entity = vehicle, coords = vec3(0, -3, 0) }
scans(8)
check('a blocked point is not drawn', #drawn == 0)
check('a blocked point is not snapped', aimed and aimed.key == nil)
sightHit = { failed = true }
scans(8)
check('a failed sight test keeps the old answer', #drawn == 0)
sightHit = { hit = true, entity = vehicle, coords = world[vehicle].coords + bones.door_dside_f + vec3(0, -0.2, 0) }
scans(8)
check('a sight ray stopping at the point counts as clear', #drawn >= 1)
sightHit = nil

-- A point whose very first sight test fails must not hold the queue
local fresh = R.add('global', 'vehicle', { name = 'fresh', label = 'Neu', distance = 5.0 }, 'res', { anchor = { bone = 'far' } })
sightHit = { failed = true }
scans(2)
sightTargets = {}
scans(8)
local seen = {}
for _, target in ipairs(sightTargets) do seen[tostring(target.y)] = true end
local kinds = 0
for _ in pairs(seen) do kinds = kinds + 1 end
check('an unanswered first sight test does not block the queue', kinds >= 2)
sightHit = nil
R.remove(fresh)
scans(2)

scans(1)
local hidesBefore = count('pillHide')
justPressed[24] = true
pump(1)
justPressed[24] = false
pump(2)
check('a click runs the selected option', doorRun == 1)
check('a finished option ends the session', not Session.isActive())
pump(2)
check('the end clears the aim', aimed == nil and not Render.isRunning())
check('the end has no pill left to hide', count('pillHide') == hidesBefore)
check('the scan forgets its target', S.current() == nil)
pump(2)
check('the threads wind down', #threads == 0)
check('the key stays held without a restart', not Session.isActive())
release()
pump(1)
check('a release after the end is harmless', not Session.isActive() and #threads == 0)

-- The check results of one press carry into the next
press()
aimsBefore = aimCalls
repeat pump(1) until aimCalls > aimsBefore
check('a second press starts with the known points', #drawn == 2)
release()
pump(2)
R.remove(door); R.remove(hood); R.remove(denied)
threads = {}

-- Near markers already on screen stay up through a press
local nearSpot = R.add('point', 'coords', { label = 'Nah' }, 'res', { show = 'near', anchor = { coords = vec3(-1, 0, 0) } })
threads = {}
rays[511] = nil
N.sync()
emptySends = 0
press()
scans(2)
check('near markers survive the press', emptySends == 0 and #drawn == 1 and drawn[1].key == 'c:-1,0,0')
release()
pump(2)
R.remove(nearSpot)
N.sync()
pump(1)
threads = {}

-- Unchecked points go first in both round robins
ray(511, 0, vec3(0, 3, 0))
local settled = {}
for i = 1, 10 do
    settled[i] = R.add('point', 'coords', { label = 'S' .. i }, 'res', { anchor = { coords = vec3(-1, 0, i * 0.01) } })
end
press()
scans(30)
check('the settled points are drawn', #drawn == 10)
local late = R.add('point', 'coords', { label = 'Spät' }, 'res', { anchor = { coords = vec3(-3, 0, 0) } })
local closest = R.add('point', 'coords', { label = 'Nächster' }, 'res', { anchor = { coords = vec3(-0.5, 0, 0) } })
aimsBefore, sightTargets = aimCalls, {}
repeat pump(1) until aimCalls >= aimsBefore + 3
check('new points are checked ahead of the others', #drawn == 12)
-- They sit at both ends of the list, a round robin could not reach both in a row
check('their sight checks are the next ones out', sightTargets[1] and sightTargets[1].x == -0.5 and sightTargets[2] and sightTargets[2].x == -3)
release()
pump(2)
for _, id in ipairs(settled) do R.remove(id) end
R.remove(late); R.remove(closest)

-- An entity without points costs nothing between walks
local boxes = R.add('model', 88, { label = 'Kiste' }, 'res', { anchor = { offset = vec3(0, 0, 0), relative = false } })
rays[511] = nil
press()
scans(4)
local classifiedBefore = typeCalls[barrel] or 0
pump(40)
check('an entity without points is left out of the scans', (typeCalls[barrel] or 0) - classifiedBefore <= 5)
check('an entity with points stays in', #drawn == 1)
release()
pump(2)
R.remove(boxes)
threads = {}

-- Scan: limits and zones
sent = {}
ray(511, 0, vec3(0, 3, 0))
local cloud = {}
for i = 1, 30 do
    cloud[i] = R.add('point', 'coords', { label = 'P' .. i }, 'res', { anchor = { coords = vec3(-1, 0, i * 0.01) } })
end
local sphere = R.addZone({ coords = vec3(0, 0.5, 0), radius = 3.0, options = { { label = 'Zone' } }, label = 'Tor' }, 'res')
local hiddenZone = R.addZone({ coords = vec3(0, 0.6, 0), radius = 3.0, drawSprite = false, options = { { label = 'Still' } } }, 'res')
local farZone = R.addZone({ coords = vec3(100, 100, 0), radius = 1.0, options = { { label = 'Weit' } } }, 'res')
press()
scans(60)
check('points respect the limit', #drawn == Config.MaxPoints)
local zoneMarks = 0
for _, point in ipairs(drawn) do
    if point.noSnap then zoneMarks = zoneMarks + 1 end
end
check('a zone marker takes a place in the limit', zoneMarks == 1)
check('a zone holding the hit joins the target', #S.current().zones == 2)
check('a far zone stays out', (function()
    for _, zone in ipairs(S.current().zones) do
        if zone.id == farZone then return false end
    end
    return true
end)())
check('a zone never snaps', aimed.key == nil or aimed.noSnap == nil)
release()
pump(2)
for _, id in ipairs(cloud) do R.remove(id) end
R.removeZone(sphere); R.removeZone(hiddenZone); R.removeZone(farZone)
threads = {}

-- Points out of reach must not crowd out a reachable one behind them
local crowd = {}
for i = 1, 24 do
    crowd[i] = R.add('point', 'coords', { label = 'Eng', distance = 0.5 }, 'res', { anchor = { coords = vec3(-1, 0, i * 0.01) } })
end
local atm = R.add('point', 'coords', { label = 'Automat' }, 'res', { anchor = { coords = vec3(-6.5, 0, 0) } })
press()
scans(6)
check('a far reachable point is drawn past nearer out of reach ones', #drawn == 1 and drawn[1].coords.x == -6.5)
release()
pump(2)
for _, id in ipairs(crowd) do R.remove(id) end
R.remove(atm)
threads = {}

-- A zone marker follows the same rule as a point: no allowed option, no marker
local gated = R.addZone({ coords = vec3(-1, 0, 0), radius = 1.0, options = { { label = 'Fraktion', groups = 'police' } } }, 'res')
groupAllowed = false
press()
scans(2)
check('a zone only for others has no marker', #drawn == 0)
groupAllowed = true
scans(2)
check('a zone with an allowed option has its marker', #drawn == 1 and drawn[1].noSnap)
world[ped].coords = vec3(-15, 0, 0)
scans(2)
check('a zone out of option reach has no marker', #drawn == 0)
world[ped].coords = vec3(0, 0, 0)
release()
pump(2)
R.removeZone(gated)

-- A zone without height limits sits far above or below the player, only the horizontal reach says anything
local openZone = R.addZone({ coords = vec3(-1, 0, 200), size = vec3(2, 2, 900), openHeight = true, options = { { label = 'Offen' } } }, 'res')
press()
scans(2)
check('an open height zone has its marker in horizontal reach', #drawn == 1 and drawn[1].noSnap)
check('an open height marker stands at the player height', drawn[1].coords.z == world[ped].coords.z)
world[ped].coords = vec3(-15, 0, 0)
scans(2)
check('an open height zone still ends at its horizontal reach', #drawn == 0)
world[ped].coords = vec3(0, 0, 0)
release()
pump(2)
R.removeZone(openZone)
local closedZone = R.addZone({ coords = vec3(-1, 0, 200), size = vec3(2, 2, 900), options = { { label = 'Hoch' } } }, 'res')
press()
scans(2)
check('a zone with a height keeps measuring in three dimensions', #drawn == 0)
release()
pump(2)
R.removeZone(closedZone)
threads = {}

-- Input: the session and its controls
fired, disabled = 0, {}
ray(511, vehicle, vec3(1, 0, 0))
local second = R.add('global', 'vehicle', { name = 'second', label = 'Zweite' }, 'res')
press()
scans(2)
check('firing is held back every frame', fired > 0)
local allDisabled = true
for _, control in ipairs({ 14, 15, 16, 17, 24, 25, 37, 140, 141, 142 }) do
    if not disabled[control] then allDisabled = false end
end
check('every listed control is disabled', allDisabled)
justPressed[14] = true
pump(1)
justPressed[14] = false
check('the wheel moves down', last('select') and last('select').index == 2)
justPressed[15] = true
pump(1)
justPressed[15] = false
check('the wheel moves up', last('select').index == 1)

-- A blocker ends the session while the key stays down
paused = true
pump(4)
check('a blocker ends the session', not Session.isActive())
check('the end cleans up after a blocker', aimed == nil and not Render.isRunning())
paused = false
pump(4)
check('no restart while the key is held', not Session.isActive())
release()
press()
check('a fresh press starts again', Session.isActive())
scans(2)
release()
press()
scans(2)
-- Scan, input and the marker frames
check('a quick press keeps the running loop', Session.isActive() and #threads == 3)
release()
check('releasing cancels', not Session.isActive())
pump(2)
check('nothing is left running', #threads == 0 and not Render.isRunning())

-- A ray can come back after the cleanup already ran
press()
pump(1)
release()
threads[1], threads[2] = threads[2], threads[1]
pump(2)
check('a late ray leaves nothing behind', S.current() == nil and aimed == nil and #threads == 0)

Config.Toggle = true
press()
check('toggle opens on press', Session.isActive())
release()
check('toggle ignores the release', Session.isActive())
press()
check('toggle closes on the next press', not Session.isActive())
pump(2)
Config.Toggle = false

-- A slow option must not hold the end of the session hostage
local resumed, holding = false, true
local slowRuns = 0
local slow = R.add('global', 'vehicle', { name = 'slow', label = 'Langsam', onSelect = function()
    slowRuns = slowRuns + 1
    while holding do coroutine.yield() end
    resumed = true
end }, 'res')
press()
scans(2)
justPressed[14] = true
pump(1)
pump(1)
justPressed[14] = false
justPressed[24] = true
pump(3)
justPressed[24] = false
check('a second click waits for the running option', slowRuns == 1)
release()
pump(2)
check('the end does not wait for a running option', aimed == nil and not Render.isRunning())

-- The old click is still running when the next session starts
press()
scans(2)
justPressed[24] = true
pump(3)
justPressed[24] = false
check('a new session runs no second click meanwhile', slowRuns == 1)
holding = false
pump(2)
check('the option finishes on its own thread', resumed)
check('the old click leaves the new session alone', Session.isActive())
scans(1)
justPressed[24] = true
pump(1)
justPressed[24] = false
pump(2)
check('clicks work again afterwards', not Session.isActive())
pump(2)
threads = {}

-- An error inside a click must not leave the button dead
local realClick, realPrintClick = Session.click, print
local clicks = 0
Session.click = function() clicks = clicks + 1; error('boom') end
_G.print = function() end
press()
scans(2)
justPressed[24] = true
pump(1)
justPressed[24] = false
pump(2)
justPressed[24] = true
pump(1)
justPressed[24] = false
pump(2)
_G.print = realPrintClick
Session.click = realClick
check('a click that failed frees the button', clicks == 2 and Session.isActive())
release()
pump(2)
threads = {}

-- Selecting with a weapon drawn: the button is still down when the session ends
press()
scans(2)
heldDown[24] = true
justPressed[24] = true
pump(1)
justPressed[24] = false
pump(2)
check('the click ended the session', not Session.isActive())
fired, disabled = 0, {}
pump(2)
check('firing stays held back while the button is down', fired >= 2 and disabled[24] and disabled[140] and disabled[141] and disabled[142])
check('only the attack controls stay blocked', not disabled[14] and not disabled[25])
press()
pump(1)
justPressed[14] = true
scans(1)
justPressed[14] = false
check('a press during the hold re-enters the running loop', last('select') ~= nil and Session.isActive())
heldDown[24] = false
release()
pump(2)
check('the hold leaves nothing running', #threads == 0)
fired, disabled = 0, {}
pump(2)
check('the controls come free once the button is up', fired == 0 and not disabled[24])

press()
scans(2)
heldDown[24] = true
release()
pump(2)
fired = 0
pump(1)
check('releasing Alt during a click holds fire too', fired == 1)
heldDown[24] = false
pump(2)
check('that hold ends with the button', #threads == 0)

R.remove(slow); R.remove(second); R.remove(general)
threads = {}

-- Without textures the session and the panel still run
local realPrint = print
_G.print = function() end
natives.CreateRuntimeTexture = function() return nil end
harness.load('client/render.lua')
sent = {}
local plain = R.add('global', 'vehicle', { name = 'plain', label = 'Ohne Marker' }, 'res')
press()
scans(2)
_G.print = realPrint
check('the panel works without markers', not EFT.Render.isRunning() and Session.isActive() and last('show').rows[1].label == 'Ohne Marker')
release()
pump(2)
R.remove(plain)
natives.CreateRuntimeTexture = function() return 1 end
harness.load('client/render.lua')
threads = {}

-- Hold: the key has to stay down on the same row
local heldRuns = 0
local timed = R.add('global', 'vehicle', { name = 'timed', label = 'Aufbrechen', hold = 200, onSelect = function() heldRuns = heldRuns + 1 end }, 'res')
local quick = R.add('global', 'vehicle', { name = 'quick', label = 'Schnell' }, 'res')
sent = {}
press()
scans(2)
check('a session names the use key', last('key') and last('key').key == 'E')
check('the panel marks the held row', last('show').rows[1].hold == 'halten')

justPressed[24], heldDown[24] = true, true
pump(2)
justPressed[24] = false
check('a press on a held row starts the fill', last('hold') and last('hold').ms == 200 and heldRuns == 0)
heldDown[24] = false
pump(2)
check('letting go early runs nothing and clears the fill', heldRuns == 0 and last('hold').ms == 0)

justPressed[24], heldDown[24] = true, true
pump(2)
justPressed[24] = false
justPressed[14] = true
pump(1)
justPressed[14] = false
pump(2)
check('another row cancels the hold', heldRuns == 0 and last('hold').ms == 0)
heldDown[24] = false
pump(1)
justPressed[15] = true
pump(1)
justPressed[15] = false

commands['+ef_target_use']()
pump(1)
check('the use key starts the same hold', last('hold').ms == 200)
commands['-ef_target_use']()
pump(2)
check('the use key cancels on release', heldRuns == 0 and last('hold').ms == 0)

commands['+ef_target_use']()
pump(8)
check('a full hold runs the option', heldRuns == 1 and last('hold').ms == 0)
commands['-ef_target_use']()
release()
pump(3)
R.remove(timed); R.remove(quick)
threads = {}

-- Built-in vehicle points
harness.load('client/defaults.lua')
local function defaultEntry(door)
    local offsets = { [4] = 1, [5] = 0 }
    local names = { [0] = 'handle_dside_f', 'handle_pside_f', 'handle_dside_r', 'handle_pside_r' }
    for _, entry in ipairs(R.forEntity(vehicle, 2, 77, nil, false)) do
        local anchor = entry.anchor
        if entry.resource == 'ef_target' and ((anchor.bone and anchor.bone == names[door]) or (anchor.offset and anchor.offset.y == offsets[door])) then
            return entry
        end
    end
end
local function defaultDoorAllowed(entity, door)
    return defaultEntry(door).options[1].canInteract(entity) and true or false
end

local count6 = 0
for door = 0, 5 do
    if defaultEntry(door) then count6 = count6 + 1 end
end
check('six default points exist', count6 == 6)
check('default points show on the key', defaultEntry(0).show == 'alt' and defaultEntry(5).show == 'alt')
check('the hood uses the relative offset', defaultEntry(4).anchor.relative == true and defaultEntry(4).anchor.offset == vec3(0.5, 1, 0.5))
check('the trunk uses the relative offset', defaultEntry(5).anchor.relative == true and defaultEntry(5).anchor.offset == vec3(0.5, 0, 0.5))

check('a closed unlocked door is allowed', defaultDoorAllowed(vehicle, 0))
natives.GetVehiclePedIsIn = function() return 9 end
check('door points rest inside a vehicle', not defaultDoorAllowed(vehicle, 0))
natives.GetVehiclePedIsIn = function() return inVehicle end
check('a missing door gets no point', (function() natives.GetIsDoorValid = function() return false end; return not defaultDoorAllowed(vehicle, 0) end)())
natives.GetIsDoorValid = function() return doorValid end
lockStatus = 2
check('a locked vehicle gets no door point', not defaultDoorAllowed(vehicle, 0))
lockStatus = 1
doorDamaged = true
check('a broken door gets no point', not defaultDoorAllowed(vehicle, 0))
doorDamaged = false

local select1 = defaultEntry(1).options[1].onSelect
select1({ entity = vehicle })
check('the owner toggles the door directly', doorCalls[1] == 'open1' and #serverEvents == 0)
doorAngle = 0.5
select1({ entity = vehicle })
check('an open door shuts', doorCalls[2] == 'shut1')
doorAngle = 0.0
owner = 2
select1({ entity = vehicle })
check('a foreign vehicle goes through the server', serverEvents[1] and serverEvents[1].name == 'ef_target:toggleDoor'
    and serverEvents[1].args[1] == 50 and serverEvents[1].args[2] == 1 and #doorCalls == 2)
networked = false
select1({ entity = vehicle })
check('a local vehicle toggles directly', doorCalls[3] == 'open1' and #serverEvents == 1)
networked, owner = true, 1

doorCalls = {}
netEvents['ef_target:toggleDoor'](50, 3)
check('the relayed event moves the door', doorCalls[1] == 'open3')
lockStatus = 2
netEvents['ef_target:toggleDoor'](50, 3)
check('a relayed request respects the lock', #doorCalls == 1)
lockStatus = 1
netEvents['ef_target:toggleDoor'](404, 3)
check('a relay for an unknown vehicle does nothing', #doorCalls == 1)

Config.DefaultPoints = false
local before = R.revision
harness.load('client/defaults.lua')
check('DefaultPoints off adds nothing', R.revision == before)

for _, name in ipairs(stubbed) do natives[name] = nil end
for _, name in ipairs({ 'Config', 'L', 'json' }) do _G[name] = nil end
harness.resetEFT()
