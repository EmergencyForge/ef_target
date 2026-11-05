# ef_target

ef_target ist das Third-Eye-Target für FiveM-Server mit [ef_lib](https://github.com/EmergencyForge/ef_lib) und ersetzt ox_target, qb-target und qtarget. Alt halten, auf ein Fahrzeug, eine Person oder eine Zone zielen, mit dem Mausrad eine Option wählen, mit Linksklick auslösen. Scripts, die für ox_target oder qb-target geschrieben sind, laufen ohne Änderung weiter.

```lua
exports.ef_target:AddPoint({
    global = 'vehicle',
    bone = 'door_dside_f',
    label = 'Fahrertür',
    options = {
        { label = 'Abschließen', icon = 'fa-solid fa-lock', onSelect = function(data) print(data.entity) end },
    },
})
```

An der Fahrertür aller Fahrzeuge erscheint ein Punkt, solange Alt gehalten wird. Mehr Beispiele stehen in [example.lua](example.lua).

## Installation

1. `ef_target` in den Resources-Ordner legen. `web/dist` ist fertig gebaut, ein Build ist nicht nötig.
2. In der `server.cfg` nach ef_lib eintragen:

```
ensure ef_lib
ensure ef_target
```

3. Läuft noch eine echte ox_target, qtarget oder qb-target, vorher stoppen und aus der `server.cfg` nehmen. ef_target meldet sich unter diesen Namen selbst (`provide`).

## Weiter

Alles Weitere steht in [DOCUMENTATION.md](DOCUMENTATION.md): Exports, Felder einer Option, `show`, Config, Umstieg von ox_target und die Lücken der qb-target-Kompatibilität.

Lizenz: GPL-3.0.
