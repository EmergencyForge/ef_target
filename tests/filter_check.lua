local harness = require('tests.harness')
local check = harness.check

local saved = {}
local function stub(name, value) saved[#saved + 1] = { name, _G[name] }; _G[name] = value end

local handlers = {}
stub('RegisterNetEvent', function(name, fn) handlers[name] = fn end)
stub('source', 1)
stub('exports', setmetatable({}, { __index = function() return { getSharedObject = function() return { PlayerLoaded = false } end } end }))
stub('GetResourceState', function() return 'missing' end)
stub('Config', nil)
harness.load('config.lua')

local function boot()
    harness.resetEFT()
    handlers = {}
    for _, f in ipairs({ 'client/eft.lua', 'client/framework/esx.lua', 'client/framework/qb.lua',
        'client/framework/ox.lua', 'client/framework/init.lua', 'client/filter.lua' }) do
        harness.load(f)
    end
    return EFT.Framework, EFT.Filter
end

-- No framework at all: every group and item requirement counts as met
local fw, F = boot()
check('no framework: groups are met', fw.hasGroup('police'))
check('no framework: items are met', fw.hasItems('bread'))

local ctx = { entity = 1, distance = 1.0, coords = vec3(0, 0, 0), bone = nil }
local calls = 0
local opt = { canInteract = function() calls = calls + 1; return true end }
F.interact(opt, ctx, 1000); F.interact(opt, ctx, 1100)
check('canInteract stays inside its budget', calls == 1)
F.interact(opt, ctx, 1260); check('it runs again after 250 ms', calls == 2)
F.interact(opt, { entity = 2, distance = 1.0 }, 1270)
check('a new entity never reuses an answer', calls == 3)
F.force(opt, ctx); check('a click always checks fresh', calls == 4)
F.reset(); F.interact(opt, ctx, 1280); check('reset clears the cache', calls == 5)
check('a throwing callback counts as no', F.interact({ canInteract = function() error('x') end }, ctx, 0) == false)
check('no callback counts as yes', F.interact({}, ctx, 0))
check('distance filters', not F.static({ distance = 2.0 }, 2.5, nil))
check('default distance is 7', F.static({}, 6.9, nil) and not F.static({}, 7.1, nil))
check('a submenu hides the home options', not F.static({}, 1.0, 'sub'))
check('a submenu shows its own options', F.static({ menuName = 'sub' }, 1.0, 'sub'))

-- ESX detected, player not loaded yet
_G.GetResourceState = function(name) return name == 'es_extended' and 'started' or 'missing' end
fw, F = boot()
check('detected framework is named', fw.name == 'es_extended')
check('before loading groups are not met', not fw.hasGroup('police') and not F.static({ groups = 'police' }, 1.0, nil))
handlers['esx:playerLoaded']({ job = { name = 'police', grade = 2 }, inventory = { { name = 'bread', count = 3 }, { name = 'water', count = 0 } } })
check('grade below the minimum fails', not F.static({ groups = { police = 3 } }, 1.0, nil))
check('grade at the minimum passes', F.static({ groups = { police = 2 } }, 1.0, nil))
check('array and string filters match by name', fw.hasGroup({ 'ems', 'police' }) and fw.hasGroup('police') and not fw.hasGroup('ems'))
check('items need all by default', fw.hasItems({ 'bread', 'water' }) == false and fw.hasItems('bread'))
check('item minimum count', fw.hasItems({ bread = 3 }) and not fw.hasItems({ bread = 4 }))
check('anyItem needs just one', F.static({ items = { 'a', 'bread' }, anyItem = true }, 1.0, nil))
handlers['esx:removeInventoryItem']('bread', 0)
check('inventory events update counts', not fw.hasItems('bread'))
handlers['esx:setJob']({ name = 'ems', grade = 0 })
check('job change replaces the group', fw.hasGroup('ems') and not fw.hasGroup('police'))

-- ox_inventory answers item questions when it runs
_G.GetResourceState = function(name) return (name == 'es_extended' or name == 'ox_inventory') and 'started' or 'missing' end
_G.exports = setmetatable({}, { __index = function(_, res)
    if res == 'ox_inventory' then return { Search = function(_, _, n) return n == 'key' and 2 or 0 end } end
    return { getSharedObject = function() return { PlayerLoaded = false } end }
end })
fw = boot()
check('ox_inventory is the item source', fw.hasItems({ key = 2 }) and not fw.hasItems('bread'))

-- ox_core: snapshot at load, then events; a nil grade removes the group
_G.GetResourceState = function(name) return name == 'ox_core' and 'started' or 'missing' end
_G.exports = setmetatable({}, { __index = function()
    return { GetPlayer = function() return { groups = { police = 2, mech = 1 } } end }
end })
fw, F = boot()
check('ox_core: groups present before the first event', fw.hasGroup({ police = 2 }) and fw.hasGroup('mech'))
handlers['ox:setGroup']('police', 3)
check('ox_core: setGroup updates the grade', fw.hasGroup({ police = 3 }))
handlers['ox:setGroup']('police', nil)
check('ox_core: a nil grade removes the group', not fw.hasGroup('police') and fw.hasGroup('mech'))

-- an adapter that throws must not abort loading
_G.GetResourceState = function(name) return name == 'es_extended' and 'started' or 'missing' end
_G.exports = setmetatable({}, { __index = function() error('boom') end })
local realPrint = print
local warned
_G.print = function(msg) if tostring(msg):find('adapter', 1, true) then warned = true else realPrint(msg) end end
local okBoot = pcall(boot)
_G.print = realPrint
check('a throwing adapter does not abort loading', okBoot and warned == true)
check('after a failed adapter nothing is filtered', EFT.Framework.name == nil and EFT.Framework.hasGroup('police'))

for i = #saved, 1, -1 do _G[saved[i][1]] = saved[i][2] end
harness.resetEFT()
