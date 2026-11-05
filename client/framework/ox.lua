EFT.Framework = EFT.Framework or {}
EFT.Framework.adapters = EFT.Framework.adapters or {}

-- ox_core keeps groups only; items come from ox_inventory
EFT.Framework.adapters.ox_core = function(fw)
    local groups = {}
    RegisterNetEvent('ox:playerLoaded', function()
        -- Groups arrive through ox:setGroup right after; start from a clean slate
        groups = {}
        fw.setGroups(groups)
    end)
    RegisterNetEvent('ox:setGroup', function(name, grade)
        groups[name] = grade
        fw.setGroups(groups)
    end)
end
