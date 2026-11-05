-- Pure zone math and the spatial grid behind the registry; no natives, so it runs in plain Lua
local Geometry = {}
EFT.Geometry = Geometry

local CELL = 50.0

local function rad(deg) return deg * math.pi / 180.0 end

function Geometry.inSphere(zone, p)
    local c = zone.coords
    local dx, dy, dz = p.x - c.x, p.y - c.y, p.z - c.z
    return dx * dx + dy * dy + dz * dz <= zone.radius * zone.radius
end

-- size is the full extent per axis, rotation turns the box around Z
function Geometry.inBox(zone, p)
    local c, s = zone.coords, zone.size
    local dx, dy = p.x - c.x, p.y - c.y
    local a = rad(zone.rotation or 0.0)
    local cos, sin = math.cos(a), math.sin(a)
    local lx = dx * cos + dy * sin
    local ly = -dx * sin + dy * cos
    return math.abs(lx) <= s.x / 2 and math.abs(ly) <= s.y / 2 and math.abs(p.z - c.z) <= s.z / 2
end

-- Ray casting in XY; the vertical range is the mean point height plus or minus half the thickness
function Geometry.inPoly(zone, p)
    local pts = zone.points
    local sumZ = 0.0
    for i = 1, #pts do sumZ = sumZ + pts[i].z end
    if math.abs(p.z - sumZ / #pts) > (zone.thickness or 4.0) / 2 then return false end

    local inside = false
    local j = #pts
    for i = 1, #pts do
        local a, b = pts[i], pts[j]
        if (a.y > p.y) ~= (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x then
            inside = not inside
        end
        j = i
    end
    return inside
end

-- Sets center, the bounding sphere radius and kind; the grid and the broad phase only look at these
function Geometry.prepare(zone)
    if zone.points then
        local n, sx, sy, sz = #zone.points, 0.0, 0.0, 0.0
        for _, v in ipairs(zone.points) do sx, sy, sz = sx + v.x, sy + v.y, sz + v.z end
        local center = vec3(sx / n, sy / n, sz / n)
        local half, far = (zone.thickness or 4.0) / 2, 0.0
        for _, v in ipairs(zone.points) do
            local dx, dy = v.x - center.x, v.y - center.y
            far = math.max(far, dx * dx + dy * dy)
        end
        zone.kind, zone.center, zone.radius = 'poly', center, math.sqrt(far + half * half)
    elseif zone.size then
        local s = zone.size
        zone.kind, zone.center = 'box', zone.coords
        zone.radius = math.sqrt(s.x * s.x + s.y * s.y + s.z * s.z) / 2
    else
        zone.kind, zone.center = 'sphere', zone.coords
        zone.radius = zone.radius or 1.0
    end
    return zone
end

local function cellRange(x, y, r)
    return math.floor((x - r) / CELL), math.floor((x + r) / CELL), math.floor((y - r) / CELL), math.floor((y + r) / CELL)
end

local Grid = {}
Grid.__index = Grid

function Geometry.grid()
    return setmetatable({ cells = {}, owned = {} }, Grid)
end

function Grid:add(zone)
    local x0, x1, y0, y1 = cellRange(zone.center.x, zone.center.y, zone.radius)
    local keys = {}
    for cx = x0, x1 do
        for cy = y0, y1 do
            local key = cx .. ':' .. cy
            local cell = self.cells[key]
            if not cell then cell = {}; self.cells[key] = cell end
            cell[zone] = true
            keys[#keys + 1] = key
        end
    end
    self.owned[zone] = keys
end

function Grid:remove(zone)
    local keys = self.owned[zone]
    if not keys then return end
    for _, key in ipairs(keys) do
        local cell = self.cells[key]
        cell[zone] = nil
        if next(cell) == nil then self.cells[key] = nil end
    end
    self.owned[zone] = nil
end

-- Zones whose bounding sphere reaches within range of p, each listed once
function Grid:near(p, range)
    local found, out = {}, {}
    local x0, x1, y0, y1 = cellRange(p.x, p.y, range)
    for cx = x0, x1 do
        for cy = y0, y1 do
            local cell = self.cells[cx .. ':' .. cy]
            if cell then
                for zone in pairs(cell) do
                    if not found[zone] then
                        found[zone] = true
                        local c = zone.center
                        local dx, dy, dz = p.x - c.x, p.y - c.y, p.z - c.z
                        local reach = range + zone.radius
                        if dx * dx + dy * dy + dz * dz <= reach * reach then out[#out + 1] = zone end
                    end
                end
            end
        end
    end
    return out
end
