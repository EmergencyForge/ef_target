EFT.Framework = EFT.Framework or {}
EFT.Framework.adapters = EFT.Framework.adapters or {}

EFT.Framework.adapters.es_extended = function(fw)
    local ESX = exports.es_extended:getSharedObject()
    local jobs, items = {}, {}

    local function publish()
        local groups = {}
        for _, job in pairs(jobs) do groups[job.name] = job.grade end
        fw.setGroups(groups)
    end

    local function setData(data)
        jobs = { job = data.job, job2 = data.job2 }
        items = {}
        for _, item in pairs(data.inventory or {}) do
            if item.count > 0 then items[item.name] = item.count end
        end
        publish()
        fw.setItems(items)
    end

    if ESX.PlayerLoaded then setData(ESX.PlayerData) end

    RegisterNetEvent('esx:playerLoaded', function(data)
        if source == '' then return end
        setData(data)
    end)
    RegisterNetEvent('esx:setJob', function(job)
        if source == '' then return end
        jobs.job = job
        publish()
    end)
    RegisterNetEvent('esx:setJob2', function(job)
        if source == '' then return end
        jobs.job2 = job
        publish()
    end)
    local function setCount(name, count)
        items[name] = count > 0 and count or nil
        fw.setItems(items)
    end
    RegisterNetEvent('esx:addInventoryItem', setCount)
    RegisterNetEvent('esx:removeInventoryItem', setCount)
end
