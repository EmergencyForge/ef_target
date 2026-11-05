-- The player's accent colour lives in ef_lib's browser storage, so it reaches Lua through an export and an event.
local Accent = {}
EFT.Accent = Accent

local FALLBACK = '#f0500a'

function Accent.parse(hex)
    if type(hex) ~= 'string' then return nil end
    local r, g, b = hex:match('^#(%x%x)(%x%x)(%x%x)$')
    if not r then return nil end
    return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

local current = FALLBACK
-- ef_lib may be older than the export, then the default stays
local ok, hex = pcall(function() return exports.ef_lib:GetAccentColor() end)
if ok and Accent.parse(hex) then current = hex end

function Accent.rgb()
    return Accent.parse(current)
end

-- The panel and key pill are NUI and need the same colour the markers use
function Accent.push()
    EFT.Nui.accent(current)
end

AddEventHandler('ef_lib:accentChanged', function(hex)
    if not Accent.parse(hex) then return end
    current = hex
    Accent.push()
end)
