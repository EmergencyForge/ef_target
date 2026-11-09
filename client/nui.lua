-- The menu page runs in a DUI and not as the NUI page: its picture is drawn into the world by Surface.
-- This is the only place that builds messages for it.
local Nui = {}
EFT.Nui = Nui

Nui.TXD, Nui.TEXTURE = 'ef_target_ui', 'menu'
-- The page centre is the anchor point, the stack hangs to the right of it
Nui.WIDTH, Nui.HEIGHT = 1024, 512

-- Created with the resource so the page has loaded long before the first key press.
-- A message sent before that is lost, the next show carries the whole state again.
local dui = CreateDui(('nui://%s/web/dist/index.html'):format(GetCurrentResourceName()), Nui.WIDTH, Nui.HEIGHT)
CreateRuntimeTextureFromDuiHandle(CreateRuntimeTxd(Nui.TXD), Nui.TEXTURE, GetDuiHandle(dui))

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then DestroyDui(dui) end
end)

local function send(message)
    SendDuiMessage(dui, json.encode(message))
end

-- Only display fields cross into the browser, callbacks and option tables stay on the Lua side
function Nui.show(rows, index, nav)
    local out = {}
    for i, row in ipairs(rows) do
        out[i] = { id = row.id, label = row.label, icon = row.icon, iconColor = row.iconColor, divider = row.divider,
            submenu = row.submenu }
    end
    send({ action = 'show', rows = out, index = index, nav = nav })
    EFT.Surface.visible(true)
end

function Nui.hide()
    send({ action = 'hide' })
    EFT.Surface.visible(false)
end

function Nui.select(index) send({ action = 'select', index = index }) end
function Nui.confirm() send({ action = 'confirm' }) end
function Nui.hold(ms) send({ action = 'hold', ms = ms }) end
function Nui.accent(hex) send({ action = 'accent', hex = hex }) end
