local harness = require('tests.harness')
local check = harness.check

local saved = {}
local function stub(name, value)
    saved[#saved + 1] = { name, _G[name] }
    harness.natives[name] = value
end

local boneAt = vec3(1, 2, 3)
stub('GetEntityBoneIndexByName', function(_, name) return name == 'missing' and -1 or 1 end)
stub('GetEntityBonePosition_2', function() return boneAt end)
stub('GetEntityModel', function() return 77 end)
stub('GetModelDimensions', function() return vec3(-1, -2, 0), vec3(1, 2, 2) end)
stub('GetOffsetFromEntityInWorldCoords', function(_, x, y, z) return vec3(x + 100, y, z) end)

harness.resetEFT()
harness.load('client/eft.lua')
-- Stand-in for the real filter so refresh can be observed call by call
local staticCalls, interactCalls, allow = {}, 0, true
EFT.Filter = {
    static = function(option, distance, menu) staticCalls[#staticCalls + 1] = option; return allow and menu == nil end,
    interact = function(_, ctx) interactCalls = interactCalls + 1; return ctx.bone ~= 'blocked' end,
}
harness.load('client/points.lua')
local P = EFT.Points

local function entry(bone, option, source)
    return { anchor = { bone = bone }, options = { option or { label = bone } }, show = 'alt', label = bone, source = source }
end

check('a missing bone gives no point', P.resolve({ anchor = { bone = 'missing' } }, 5) == nil)
check('a bone resolves to its position', P.resolve({ anchor = { bone = 'door' } }, 5) == boneAt)
check('a relative offset scales by the model size',
    P.resolve({ anchor = { offset = vec3(0.5, 0.5, 0.5), relative = true } }, 5) == vec3(100, 0, 1))
check('an absolute offset is passed as is',
    P.resolve({ anchor = { offset = vec3(1, 2, 3), relative = false } }, 5) == vec3(101, 2, 3))
check('coords anchors need no entity', P.resolve({ anchor = { coords = vec3(4, 5, 6) } }, nil) == vec3(4, 5, 6))

local pts = P.collect(5, { entry('door'), entry('door'), entry('wheel'), { options = { { label = 'general' } } } }, vec3(0, 0, 0))
check('two scripts on one bone share a point', #pts == 2 and #pts[1].entries == 2 and pts[1].key == '5:b:door')
check('entries without an anchor stay out', #pts == 2)
check('a point starts unchecked with its label', pts[1].visible == nil and pts[1].label == 'door' and pts[1].entity == 5)
check('unresolvable anchors are dropped', #P.collect(5, { entry('missing') }, vec3(0, 0, 0)) == 0)

local cpts = P.collect(nil, { { anchor = { coords = vec3(1, 2, 3) }, options = { {} } } }, vec3(0, 0, 0))
check('coords points use the c: key', cpts[1].key == 'c:1,2,3' and cpts[1].entity == nil)
local opts = P.collect(5, { { anchor = { offset = vec3(1, 2, 3), relative = true }, options = { {} } } }, vec3(0, 0, 0))
check('offset points use the o: key', opts[1].key == '5:o:1,2,3')

-- close anchors merge only when they come from one option
local source, other = { label = 's' }, { label = 'o' }
local function at(x, src)
    return { anchor = { coords = vec3(x, 0, 0) }, options = { { label = 'x' } }, source = src }
end
check('anchors of one option under 0.4 m merge', #P.collect(nil, { at(0, source), at(0.3, source) }, vec3(0, 0, 0)) == 1)
check('the first of the merged anchors stays', P.collect(nil, { at(0, source), at(0.3, source) }, vec3(0, 0, 0))[1].coords.x == 0)
check('anchors 0.5 m apart stay', #P.collect(nil, { at(0, source), at(0.5, source) }, vec3(0, 0, 0)) == 2)
check('close anchors of different options stay', #P.collect(nil, { at(0, source), at(0.3, other) }, vec3(0, 0, 0)) == 2)
check('entries without a source never merge by distance', #P.collect(nil, { at(0), at(0.3) }, vec3(0, 0, 0)) == 2)

local thirty = {}
for i = 1, 30 do thirty[i] = { key = 'p' .. i, distance = 31 - i } end
thirty[30].key = 'nearest'
local picked = P.pick(thirty, 24)
check('pick keeps the nearest', picked[1].key == 'nearest' and #picked == 24 and picked[24].distance == 24)
check('pick leaves its input alone', thirty[1].key == 'p1')
check('collect fills the distance', P.collect(nil, { at(3) }, vec3(0, 4, 0))[1].distance == 5)

local a, b = { sx = 0.51, sy = 0.5, visible = true }, { sx = 0.49, sy = 0.47, visible = true }
check('the closest to the centre wins', P.snap({ b, a }, 0.035, 1.78) == a)
check('an invisible point is never snapped', P.snap({ { sx = 0.5, sy = 0.5, visible = false } }, 0.035, 1.78) == nil)
check('outside the radius there is no snap', P.snap({ { sx = 0.6, sy = 0.5, visible = true } }, 0.035, 1.78) == nil)
check('a zone marker is never snapped', P.snap({ { sx = 0.5, sy = 0.5, visible = true, noSnap = true } }, 0.035, 1.78) == nil)
-- 0.03 across is 0.0534 screen heights at 16:9, the same offset down is only 0.03
check('x is scaled by the aspect', P.snap({ { sx = 0.53, sy = 0.5, visible = true } }, 0.035, 1.78) == nil
    and P.snap({ { sx = 0.5, sy = 0.53, visible = true } }, 0.035, 1.78) ~= nil)
check('a point without a screen position is skipped', P.snap({ { visible = true } }, 0.035, 1.78) == nil)

-- refresh: one call checks one point, a point appears only after its own check
local function rp(bone, option)
    return { coords = vec3(1, 0, 0), entity = 9, visible = false, entries = { entry(bone, option) } }
end
local list = { rp('a'), rp('b'), rp('blocked') }
local ctx = { playerCoords = vec3(0, 0, 0), menu = nil }
P.refresh(list, ctx, 1000)
check('refresh checks only the first point', list[1].visible and not list[2].visible and not list[3].visible and #staticCalls == 1)
P.refresh(list, ctx, 1000)
check('the next call moves on', list[2].visible and not list[3].visible and #staticCalls == 2)
P.refresh(list, ctx, 1000)
check('canInteract can hide a point', list[3].visible == false)
P.refresh(list, ctx, 1000)
check('the cursor wraps around', #staticCalls == 4 and staticCalls[4] == list[1].entries[1].options[1])
allow = false
P.refresh(list, ctx, 1000)
check('a point turns invisible again', list[2].visible == false)
allow = true
interactCalls = 0
P.refresh({ rp('a') }, { playerCoords = vec3(0, 0, 0), menu = 'sub' }, 1000)
check('the menu is passed to the static filter', interactCalls == 0)
P.refresh({}, ctx, 1000)
check('an empty list is fine', true)

local waiting = rp('fresh')
waiting.visible = nil
local settledList = { rp('a'), rp('b'), waiting }
P.refresh(settledList, ctx, 1000)
check('an unchecked point goes first', waiting.visible == true and not settledList[1].visible and not settledList[2].visible)

for i = #saved, 1, -1 do harness.natives[saved[i][1]] = saved[i][2] end
harness.resetEFT()
