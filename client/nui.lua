-- Thin wrapper over SendNuiMessage so the rest of the client never builds NUI payloads by hand.
local Nui = {}
EFT.Nui = Nui

local function send(message)
    SendNuiMessage(json.encode(message))
end

-- Only display fields cross into the browser, callbacks and option tables stay on the Lua side
function Nui.show(rows, title, index, path, nav)
    local out = {}
    for i, row in ipairs(rows) do
        out[i] = { id = row.id, label = row.label, icon = row.icon, iconColor = row.iconColor, divider = row.divider,
            submenu = row.submenu, hold = row.hold and L('halten') or nil }
    end
    send({ action = 'show', rows = out, title = title, index = index, path = path, nav = nav })
end

function Nui.select(index) send({ action = 'select', index = index }) end
function Nui.hide() send({ action = 'hide' }) end
function Nui.pill(key, label, hold) send({ action = 'pill', key = key, label = label, hold = hold and L('halten') or nil }) end
function Nui.pillPos(x, y) send({ action = 'pillPos', x = x, y = y }) end
function Nui.pillHide() send({ action = 'pillHide' }) end
function Nui.hold(ms) send({ action = 'hold', ms = ms }) end
function Nui.key(key) send({ action = 'key', key = key }) end
function Nui.accent(hex) send({ action = 'accent', hex = hex }) end
