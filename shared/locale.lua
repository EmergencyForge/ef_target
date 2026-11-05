-- Visible texts are written in German. With Config.Locale = 'en' they are looked up here, anything missing stays German.
local en = {
    ['Fahrzeug'] = 'Vehicle',
    ['Person'] = 'Person',
    ['Objekt'] = 'Object',
    ['halten'] = 'hold',
    ['Zielen'] = 'Aim',
    ['Interagieren'] = 'Interact',
    ['Fahrertür'] = 'Driver door',
    ['Beifahrertür'] = 'Passenger door',
    ['Tür hinten links'] = 'Rear left door',
    ['Tür hinten rechts'] = 'Rear right door',
    ['Motorhaube'] = 'Hood',
    ['Kofferraum'] = 'Trunk',
    ['Öffnen/Schließen'] = 'Open/Close',
    ['Rad auf'] = 'Wheel up',
    ['Rad ab'] = 'Wheel down',
    ['Entf'] = 'Del',
    ['Einfg'] = 'Ins',
    ['Ende'] = 'End',
    ['Pos1'] = 'Home',
    ['Bild auf'] = 'PgUp',
    ['Bild ab'] = 'PgDn',
    ['Strg'] = 'Ctrl',
    ['Leer'] = 'Space',
}

function L(text, ...)
    if Config.Locale == 'en' then text = en[text] or text end
    if select('#', ...) > 0 then return text:format(...) end
    return text
end
