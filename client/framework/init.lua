EFT.Framework = EFT.Framework or {}
local fw = EFT.Framework
fw.adapters = fw.adapters or {}

local groups, items, itemLookup, groupCheck = {}, {}, nil, nil
local citizenId, jobType
fw.name = nil

function fw.setGroups(tbl) groups = tbl end
function fw.setItems(tbl) items = tbl end
function fw.setItemLookup(fn) itemLookup = fn end
function fw.setGroupCheck(fn) groupCheck = fn end
function fw.setIdentity(id, kind) citizenId, jobType = id, kind end
-- Only qb-core and Qbox know these, nil means the framework has no answer
function fw.citizenId() return citizenId end
function fw.jobType() return jobType end

-- Turns a string, an array or a { name = value } table into name/value pairs
local function pairsOf(filter, default)
    local out = {}
    if type(filter) == 'string' then
        out[1] = { filter, default }
    elseif type(filter) == 'table' then
        for k, v in pairs(filter) do
            if type(k) == 'number' then out[#out + 1] = { v, default } else out[#out + 1] = { k, v } end
        end
    end
    return out
end

function fw.hasGroup(filter)
    if not fw.name or filter == nil then return true end
    if groupCheck then return groupCheck(filter) end
    for _, p in ipairs(pairsOf(filter, 0)) do
        local grade = groups[p[1]]
        if grade and grade >= p[2] then return true end
    end
    return false
end

function fw.hasItems(filter, anyItem)
    if filter == nil or (not fw.name and not itemLookup) then return true end
    local wanted = pairsOf(filter, 1)
    if #wanted == 0 then return true end
    for _, p in ipairs(wanted) do
        local count = itemLookup and itemLookup(p[1]) or items[p[1]] or 0
        local met = count >= p[2]
        if met and anyItem then return true end
        if not met and not anyItem then return false end
    end
    return not anyItem
end

-- Order matters: ox_core wins over a leftover es_extended and qbx_core over qb-core
for _, name in ipairs({ 'ox_core', 'es_extended', 'qbx_core', 'qb-core' }) do
    if GetResourceState(name) == 'started' then
        fw.name = name
        local ok, err = pcall(fw.adapters[name], fw)
        if not ok then
            -- A broken adapter must not take the whole client script down
            print(('ef_target: framework adapter %s failed: %s'):format(name, tostring(err)))
            fw.name = nil
            groups, items, groupCheck = {}, {}, nil
            citizenId, jobType = nil, nil
        end
        break
    end
end

if GetResourceState('ox_inventory') == 'started' then
    fw.setItemLookup(function(name) return exports.ox_inventory:Search('count', name) or 0 end)
end
