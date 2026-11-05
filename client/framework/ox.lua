EFT.Framework = EFT.Framework or {}
EFT.Framework.adapters = EFT.Framework.adapters or {}

-- ox_core keeps groups only; items come from ox_inventory
EFT.Framework.adapters.ox_core = function(fw)
    local groups = {}

    -- Snapshot for the case that ef_target starts after the player has loaded
    local function snapshot()
        local player = exports.ox_core:GetPlayer()
        local current = player and (player.groups or (player.get and player.get('groups')))
        groups = {}
        for name, grade in pairs(current or {}) do groups[name] = grade end
        fw.setGroups(groups)
    end

    snapshot()
    RegisterNetEvent('ox:playerLoaded', snapshot)
    RegisterNetEvent('ox:setGroup', function(name, grade)
        -- A nil grade means the group was removed
        groups[name] = grade
        fw.setGroups(groups)
    end)
end
