EFT.Framework = EFT.Framework or {}
EFT.Framework.adapters = EFT.Framework.adapters or {}

-- ox_core keeps groups private, so every check asks it directly; items come from ox_inventory
EFT.Framework.adapters.ox_core = function(fw)
    fw.setGroupCheck(function(filter)
        local ok, result = pcall(function() return exports.ox_core:CallPlayer('getGroup', filter) end)
        if not ok then return false end
        -- getGroup answers a grade for a string filter, a { name, grade } pair for a table filter
        return type(result) == 'number' or (type(result) == 'table' and next(result) ~= nil)
    end)
end
