# ef_target Dokumentation

ef_target ist ein Third-Eye-Target für FiveM. Es braucht ef_lib, kennt feste Punkte an Bones, Offsets und Koordinaten und beantwortet die Exports von ox_target, qb-target und qtarget.

## Installation

1. `ef_target` in den Resources-Ordner legen. `web/dist` liegt gebaut bei.
2. In die `server.cfg`, ef_lib zuerst:

```
ensure ef_lib
ensure ef_target
```

ef_lib muss vor ef_target starten. Die Akzentfarbe kommt von dort: ef_target fragt `GetAccentColor` bei ef_lib ab und folgt dem Event `ef_lib:accentChanged`. Eine ef_lib ohne diesen Export zeigt `#f0500a`.

Das Manifest enthält `provide 'ox_target'`, `provide 'qb-target'` und `provide 'qtarget'`. Scripts, die mit `GetResourceState('ox_target') == 'started'` prüfen, sehen ef_target.

## Bedienung

Alt halten (`LMENU`, in den FiveM-Tastenbelegungen änderbar). In der Bildmitte dreht sich eine Raute aus vier Ecken ein, beim Loslassen dreht sie sich wieder heraus, Punkte in Reichweite erscheinen als kleine Rauten. Trifft der Strahl eine Entity oder Zone, oder liegt ein Punkt nahe der Bildmitte, schließt und füllt sich die Raute in der Akzentfarbe aus ef_lib, und das Panel zeigt die Optionen.

- Mausrad wählt die Option, Linksklick oder E löst aus. Bei nur einer Option reicht der Klick.
- Optionen mit `hold` zeigen "halten": Taste gedrückt lassen, die Zeile füllt sich. Loslassen oder eine andere Zeile wählen bricht ab.
- Rechtsklick geht im Untermenü eine Ebene zurück und landet auf der Zeile, von der es kam.
- Alt loslassen bricht ab.
- Es gibt keine Bedienung mit dem Mauszeiger. Kamera und Laufen bleiben frei, die NUI nimmt keinen Fokus.
- Solange Alt aktiv ist, sind Schießen, Zielen und Nahkampf gesperrt, das Mausrad schaltet keine Waffe um.
- Alt endet von selbst bei Pausenmenü, Tod, NUI-Fokus (etwa ein offenes Menü einer anderen Resource), laufendem Fortschrittsbalken von ef_lib oder ox_lib und `DisableTargeting(true)`.

Rastet die Raute auf einem Punkt ein, stehen dessen Optionen oben und sind vorausgewählt. Nach einer Trennlinie folgen die allgemeinen Optionen der Entity. Ein Punkt wird nur gezeichnet, wenn mindestens eine seiner Optionen für den Spieler erlaubt ist. Zonen bekommen eine kleine Raute am Mittelpunkt, die nicht einrastet. `drawSprite = false` schaltet sie ab.

Eingebaut sind Punkte an den vier Türgriffen (ohne Griff-Bone an der Tür), der Motorhaube und dem Kofferraum aller Fahrzeuge. `Config.DefaultPoints = false` schaltet sie ab.

## Config

```lua
Config = {
    Key = 'LMENU',           -- Taste zum Öffnen
    UseKey = 'E',            -- löst wie Linksklick die markierte Option aus, auch an near-Punkten
    Toggle = false,          -- true: einmal drücken öffnet, nochmal schließt
    Reticle = {
        Thickness = 2.0,     -- Strichstärke der eigenen Raute in Pixeln bei 1080p, 1.0 bis 3.5
        CenterDot = false,   -- Punkt in der Mitte der eigenen Raute
    },
    SnapRadius = 0.035,      -- Anteil der Bildhöhe, in dem die Raute auf einen Punkt springt
    MaxPoints = 24,          -- so viele Punkte werden gleichzeitig gezeichnet, die nächsten gewinnen
    DefaultPoints = true,    -- eingebaute Fahrzeugpunkte
    DefaultDistance = 7.0,   -- Reichweite einer Option ohne eigenes distance, in Metern
    RayLength = 20.0,        -- Länge des Strahls
    Locale = 'de',           -- 'de' oder 'en'
}
```

Die Tasten sind nur die Voreinstellung, Spieler ändern sie in den FiveM-Einstellungen.

## Exports

Alles, was eine Ressource hinzufügt, wird entfernt, wenn sie stoppt. Jeder Add-Aufruf gibt eine `id` zurück.

```lua
local id = exports.ef_target:AddPoint(data)
exports.ef_target:AddGlobal('ped', options)     -- 'ped', 'vehicle', 'object', 'player'
exports.ef_target:AddModel(models, options)     -- Hash, Name oder Liste davon
exports.ef_target:AddEntity(entity, options)    -- lokal oder vernetzt
exports.ef_target:AddBoxZone(data)
exports.ef_target:AddSphereZone(data)
exports.ef_target:AddPolyZone(data)
exports.ef_target:Remove(id)                    -- Punkt, Modell, Entity oder Zone
exports.ef_target:DisableTargeting(state)
exports.ef_target:IsActive()
```

`options` ist eine Option oder eine Liste davon.

### AddPoint

| Feld | Bedeutung |
| --- | --- |
| `global` | `'ped'`, `'vehicle'`, `'object'`, `'player'` |
| `model` | Modell oder Liste, mit `joaat('name')` |
| `entity` | Entity-Handle |
| `coords` | Weltposition, dann ist kein `bone` oder `offset` nötig |
| `bone` | Bone-Name, bei `global`, `model` und `entity` |
| `offset` | `vec3` in Metern von der Entity aus, statt `bone` |
| `show` | `'alt'` (Standard) oder `'near'` |
| `distance` | Reichweite, gilt für Optionen ohne eigenes `distance` |
| `label` | Titel des Panels |
| `options` | Optionen |

Genau eins von `global`, `model`, `entity`, `coords` ist nötig. Bei den drei ersten außerdem `bone` oder `offset`, sonst wirft der Aufruf einen Fehler.

### show

`alt`: Der Punkt erscheint nur bei gehaltenem Alt.

`near`: Der Punkt erscheint ohne Taste, sobald der Spieler in `distance` ist und mindestens eine Option erlaubt ist. Der nächste zeigt eine Tastenpille mit `E` und dem Text der ersten erlaubten Option, `E` führt sie aus. Hat der Punkt mehrere Optionen, wählt der Spieler sie bei gehaltenem Alt im Panel. Eine Option, die nur ein Untermenü öffnet, nimmt die Pille nicht. Öffnen alle Optionen eines `near`-Punkts nur ein Untermenü, bekommt er weder Marker noch Pille, außer bei gehaltenem Alt. Im Fahrzeug erscheinen `near`-Punkte nicht. Ohne `near`-Punkte läuft im Leerlauf nichts.

### Zonen

```lua
exports.ef_target:AddBoxZone({ name = 'x', coords = vec3(..), size = vec3(2, 1, 2), rotation = 70.0, options = {} })
exports.ef_target:AddSphereZone({ coords = vec3(..), radius = 2.0, options = {} })
exports.ef_target:AddPolyZone({ points = { vec3(..), vec3(..), vec3(..) }, thickness = 4.0, options = {} })
```

`size` ist die volle Ausdehnung je Achse, `rotation` dreht die Box um Z. Bei Polyzonen gilt die Höhe der Punkte im Mittel, `thickness` ist die Gesamthöhe. Weitere Felder: `name` (für `Remove` und gleiche Namen in mehreren Zonen), `label` (Titel des Panels), `drawSprite`. Ein `Remove` mit dem Namen entfernt alle Zonen dieses Namens.

### Felder einer Option

| Feld | Bedeutung |
| --- | --- |
| `label` | Text |
| `icon` | Font-Awesome-Klasse, `'fa-solid fa-lock'` |
| `iconColor` | Farbe des Icons |
| `name` | Name, ein erneutes Hinzufügen mit gleichem Namen ersetzt die alte Option |
| `distance` | Reichweite in Metern, sonst `Config.DefaultDistance` oder das `distance` des Punkts |
| `groups` | Job oder Gruppe: `'police'`, `{ 'police', 'sheriff' }` oder `{ police = 2 }` (ab Rang) |
| `items` | Item oder Liste, `{ bread = 2 }` mit Menge |
| `anyItem` | `true`: ein Item aus der Liste reicht |
| `canInteract` | Funktion `(entity, distance, coords, name, bone)`, gibt `true` oder `false` zurück |
| `menuName` | Menü, in dem die Option steht. Ohne Wert steht sie im Hauptmenü |
| `openMenu` | Menüname, der beim Auswählen geöffnet wird. `'home'` geht zurück |
| `hold` | Millisekunden, die die Taste gedrückt bleiben muss. Ohne Wert löst der Druck sofort aus |
| `bones`, `offset`, `absoluteOffset` | Für Scripts aus ox_target, siehe unten |

Als Ziel genau eins aus `onSelect`, `export`, `event`, `serverEvent`, `command`.

`onSelect`, `export` und `event` bekommen eine Tabelle mit `entity`, `coords`, `distance`, `zone` (id, nur bei Zonen), `point` (`key`, `coords`, nur bei Punkten) und den übrigen Feldern der Option. `coords` und `distance` gehören bei einem Punkt zum Punkt, sonst zum Treffer. `serverEvent` bekommt dieselbe Tabelle, `entity` ist dort die Net-ID, `0` wenn die Entity nicht vernetzt ist. Bei `export` wird `exports[resource][export]` aufgerufen, `resource` ist die hinzufügende Ressource oder das Feld `resource` der Option.

`canInteract` läuft für das aktuelle Ziel höchstens alle 250 ms je Option. Für `groups` und `items` erkennt ef_target ESX, QBCore, Qbox oder ox_core und ox_inventory. Ohne Framework gelten sie als erfüllt, wie bei ox_target.

Untermenü, Beispiel in `example.lua`: Eine Option mit `openMenu = 'ausweis'` öffnet das Menü, die Optionen mit `menuName = 'ausweis'` stehen darin. Der Pfad steht oben im Panel, Rechtsklick geht zurück.

## Umstieg von ox_target

1. ox_target stoppen und aus der `server.cfg` nehmen, `ensure ef_target` nach `ef_lib` eintragen.
2. Scripts bleiben, wie sie sind. Alle 24 Exports aus `client/api.lua` von ox_target 1.18.1 gibt es.
3. `bones`- und `offset`-Optionen anderer Scripts werden zu sichtbaren Rauten. Ein Bone-Array ergibt eine Raute je Bone, der am Fahrzeug vorhanden ist. Liegen zwei Anker einer Option näher als 0,4 m beieinander, bleibt der erste. `offset` in diesen Optionen sind Anteile der Entity-Box (0 bis 1), mit `absoluteOffset` Meter. Nur in `AddPoint` ist `offset` immer in Metern.
4. Läuft eine echte ox_target neben ef_target, steht das in der Konsole. Die Namen `ox_target` und `qtarget` sind dann gesperrt, weil ox_target beide bedient. Die Exports von `qb-target` bedient ef_target weiter. Erkannt wird das einmal beim Start, eine später gestartete echte Ressource sieht ef_target nicht.

Unterschiede zu ox_target:

- Box- und Polyzonen decken die Höhe von `minZ` bis `maxZ` ab, wie bei PolyZone. ox_target verschiebt die Box um die halbe Höhe. Fehlt eine der Grenzen, ist die Höhe um die Mitte offen (450 m nach oben und unten).
- Die Callbacks von lib.zones (`onEnter`, `onExit`, `inside`) laufen an Zonen nicht.
- `getTargetOptions` liefert eine einfache Tabelle (`global`, `model`, `entity`, `localEntity`, ohne Entity statt `global` dann `globalTarget`, dazu `__global`), ohne `size`, `wipe` und `set`.
- Lokale Entities, die nicht mehr existieren, werden nicht aufgeräumt, die Optionen bleiben bis `Remove` oder bis die Ressource stoppt. Vernetzte Entities räumt der Server alle 10 s auf.
- `removeModel`, `removeEntity` und `removeLocalEntity` ohne Namen leeren den Schlüssel auch für andere Ressourcen, wie bei ox_target.

## Umstieg von qb-target und qtarget

Maßstab ist qb-target 5.5.0 (Commit a3ea78b). Es gibt `AddBoxZone`, `AddPolyZone`, `AddCircleZone`, `AddEntityZone`, `RemoveZone`, `AddTargetBone`, `RemoveTargetBone`, `AddTargetEntity`, `RemoveTargetEntity`, `AddTargetModel`, `RemoveTargetModel`, `AddGlobalPed`, `AddGlobalVehicle`, `AddGlobalObject`, `AddGlobalPlayer`, die zugehörigen `RemoveGlobal...` sowie die qtarget-Namen `Ped`, `Vehicle`, `Object`, `Player` und ihre `Remove...`. `job`, `gang`, `jobType`, `citizenid`, die `exclude`-Felder, `item`, `required_item`, `event` mit `type` (`client`, `server`, `command`, `qbcommand`) und `action` werden übersetzt.

### Lücken

Diese Exports gibt es nicht. Ein Aufruf wirft den Fehler "No such export":

- `AddComboZone`, `AddGlobalType`, `RemoveGlobalType`
- `AllowTargeting`, `DisableTarget`, `IsTargetActive`, `IsTargetSuccess`
- `GetZoneData` und die übrigen `Get...`- und `Update...`-Helfer
- `RaycastCamera`, `CheckEntity`, `CheckBones`, `DisableNUI`, `EnableNUI`, `LeftTarget`, `DrawOutlineEntity`
- `SpawnPed`, `DeletePeds`, `RemoveSpawnedPed`, `GetPeds`, `UpdatePedsData`

Peds, die ein Script über `SpawnPed` anlegen ließ, muss es selbst erzeugen und mit `AddTargetEntity` oder `AddTargetModel` versehen.

Diese Felder werden gelesen und ignoriert: `useZ`, `num`, `targeticon`, `drawColor`, `successDrawColor`, `drawDistance`.

Anders als in qb-target:

- `coords` in der Antwort ist der Treffpunkt des Strahls, `distance` der Abstand zum Treffer.
- Ein `serverEvent` bekommt als `entity` die Net-ID, bei nicht vernetzten Entities `0`.
- Bei Zonen ist `entity` `nil`.
- `AddEntityZone` hängt die Optionen an die Entity, es gibt keine mitwandernde Zone um sie.
- `canInteract` bekommt `(entity, distance, option)` wie in qb-target. Das gilt auch für die Exports von `qtarget`, beide Namen teilen eine Tabelle.
- `job` allein ohne Framework gilt als erfüllt (wie `groups`). `gang`, `citizenid` und die `exclude`-Felder bleiben ohne Framework verborgen, ebenso `jobType`. ESX kennt keine Gangs, `citizenid` und `jobType`.
- Ein `job`, `gang` oder `jobType` von `'all'` ist keine Einschränkung. `excludejob`, `excludegang` und `excludejobType` mit `'all'` verbergen die Option für alle.
- `RemoveTargetBone` und `RemoveGlobal...` lassen die eingebauten Fahrzeugpunkte stehen, auch ohne Labels.
- Die Reichweite einer Option ist höchstens das `distance` des Aufrufs, Standard `Config.DefaultDistance`.

## Prüfung

```
lua tests/run.lua
```

Die Tests laufen mit reinem Lua außerhalb von FiveM. Das Panel wird in `web/` mit `bun run build` gebaut, `web/preview.html` zeigt Panel und Pille im Browser.

## Lizenz

GPL-3.0. Es wurde kein Code aus ox_target übernommen, nur die Namen der Exports.
