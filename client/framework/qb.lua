EFT.Framework = EFT.Framework or {}
EFT.Framework.adapters = EFT.Framework.adapters or {}

local function gradeOf(entry)
    return type(entry.grade) == 'table' and entry.grade.level or entry.grade or 0
end

-- qb-core and qbx_core share the PlayerData layout and both client events
local function build(getData)
    return function(fw)
        local function setData(data)
            if not data then return end
            local groups = {}
            if data.job then groups[data.job.name] = gradeOf(data.job) end
            if data.gang then groups[data.gang.name] = gradeOf(data.gang) end
            local items = {}
            for _, item in pairs(data.items or {}) do
                items[item.name] = (items[item.name] or 0) + (item.amount or item.count or 0)
            end
            fw.setGroups(groups)
            fw.setItems(items)
            fw.setIdentity(data.citizenid, data.job and data.job.type)
        end

        setData(getData())
        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() setData(getData()) end)
        RegisterNetEvent('QBCore:Player:SetPlayerData', setData)
    end
end

EFT.Framework.adapters['qb-core'] = build(function()
    return exports['qb-core']:GetCoreObject().Functions.GetPlayerData()
end)
EFT.Framework.adapters.qbx_core = build(function()
    return exports.qbx_core:GetPlayerData()
end)
