# Wegweiser

**A quest route planner for World of Warcraft: Forever.**
Wegweiser orders the quests in your current zone into a sensible route – short paths, no place visited twice, and no area cleared twice just because another quest wants something there later.

*[Deutsche Beschreibung weiter unten](#deutsch)*

![Interface: 16001](https://img.shields.io/badge/WoW%20Forever-1.60.1-orange) ![License: MIT](https://img.shields.io/badge/license-MIT-blue)

---

## Why?

Most quest helpers show *everything* on the map and leave the planning to you. They don't notice that the ravine you're about to fight through holds objectives for two more quests – one waiting in Orgrimmar, one unlocked by a follow-up. Wegweiser does, and tells you before you walk in.

It stays small on purpose: one panel, a few map numbers, almost no settings.

## Features

- **Route panel** – numbered stops for your current zone. Quests at the same place are grouped into one stop. Shows progress, distance, *Turn in* (green) and *Accept* (blue).
- **Suggestions** – quests you can pick up in the zone right now, filtered by level (no grey quests), race, class, profession and prerequisites. Holiday, reputation and repeatable quests are left out.
- **Area overlap** – for every stop, Wegweiser checks which other quests have objectives in the same area:
  - available in this zone → **accepted beforehand automatically**, the row shows **+1**
  - quest giver in another zone → **"Pick up first in …"** section at the top of the panel
  - available soon (follow-up quest or up to 2 levels ahead) → **!** marker with a tip to park the stop
- **You stay in control** – shift-click pins a stop as next, ctrl-click parks it for later, right-click hides a suggestion.
- **World map numbers** – small badges next to Blizzard's quest icons, same size at every zoom level.
- **Auto-tracking** – the next stop is tracked automatically (quest or map pin).
- **German and English** – follows the client language.

## Installation

1. Download this repository (*Code → Download ZIP*) and copy the folder **`Wegweiser`** into
   `World of Warcraft/<Forever client folder>/Interface/AddOns/`.
   Tip: in the CurseForge app, right-click any installed addon → open folder to find the right path.
2. **Optional, recommended:** install **QuestieDB** for suggestions and area overlap.
   It ships with [Questie](https://www.curseforge.com/wow/addons/questie) on CurseForge.
   If you don't want Questie itself, disable *Questie* in the addon list and keep *QuestieDB* enabled – it has no UI of its own.
3. Tick *Load out of date AddOns* if the addon is greyed out.

Without QuestieDB, Wegweiser still sorts the quests in your log – just without suggestions and overlap hints.

## Usage

| Action | Effect |
|---|---|
| Click a row | track this stop |
| Shift-click | pin as next stop (again: unpin) |
| Ctrl-click | park for later (again: schedule again) |
| Right-click | hide a suggestion |
| Arrow button | recalculate now |
| Gear button | settings and a legend of all controls |

**Commands:** `/ww` toggle panel · `/ww options` · `/ww refresh` · `/ww track` · `/ww pins` · `/ww suggest` · `/ww grey` · `/ww unignore` · `/ww unpark` · `/ww reset`

Settings are also available under *Esc → Options → AddOns → Wegweiser*.

## How it works

- Quest positions in your log come straight from the client (`C_QuestLog.GetQuestsOnMap`), so even brand-new Forever quests are covered.
- Suggestions and objective areas come from [QuestieDB](https://github.com/Questie/QuestieDB) through its public consumer API. Wegweiser builds a small index in the background after login (about 5 ms per frame).
- The route is an open path from your position: clustering, nearest neighbour, then 2-opt and relocation moves. Accept stops are pulled towards the front so you can do their objectives on the way, and *accept before objective area* is a hard constraint.

## Known limitations

- Planning stays within the current zone (no flight paths yet).
- Quest chains are not planned ahead automatically – Wegweiser tells you about them, you decide (pin / park).
- Data quality for new Forever content depends on QuestieDB, which is updated almost daily.

## Credits & license

- Quest data: [QuestieDB](https://github.com/Questie/QuestieDB) by the Questie team. Wegweiser contains **no** Questie code or data – it only reads QuestieDB at runtime as an optional dependency.
- Wegweiser itself is released under the [MIT License](LICENSE).

---

<a name="deutsch"></a>

## Deutsch

**Ein Routenplaner für Quests in World of Warcraft: Forever.**
Wegweiser bringt die Quests in deiner aktuellen Zone in eine sinnvolle Reihenfolge: kurze Wege, kein Ort doppelt – und kein Gebiet zweimal, nur weil eine andere Quest später dort auch etwas will.

### Warum?

Die meisten Quest-Helfer zeigen *alles* auf der Karte und überlassen dir die Planung. Sie merken nicht, dass in der Schlucht, durch die du dich gleich kämpfst, auch Ziele von zwei weiteren Quests liegen – eine wartet in Orgrimmar, eine wird durch eine Folgequest freigeschaltet. Wegweiser merkt es und sagt es dir, bevor du losläufst.

Bewusst schlank: ein Panel, ein paar Nummern auf der Karte, kaum Einstellungen.

### Funktionen

- **Routen-Panel** – nummerierte Orte in deiner Zone, Quests am gleichen Ort zusammengefasst. Mit Fortschritt, Distanz, *Abgeben* (grün) und *Annehmen* (blau).
- **Vorschläge** – Quests, die du jetzt in der Zone annehmen kannst, gefiltert nach Stufe (keine grauen), Rasse, Klasse, Beruf und Vorquests. Feiertags-, Ruf- und wiederholbare Quests werden weggelassen.
- **Gebietsüberschneidung** – für jeden Ort prüft Wegweiser, welche anderen Quests im selben Gebiet Ziele haben:
  - in dieser Zone verfügbar → wird **automatisch vorher angenommen**, die Zeile zeigt **+1**
  - Questgeber in einer anderen Zone → Abschnitt **«Vorher holen in …»** oben im Panel
  - bald verfügbar (Folgequest oder bis 2 Stufen voraus) → **!** mit dem Tipp, den Ort zu parken
- **Du behältst die Kontrolle** – Shift-Klick nagelt einen Ort als Nächstes fest, Strg-Klick parkt ihn auf später, Rechtsklick blendet einen Vorschlag aus.
- **Nummern auf der Weltkarte** – kleine Abzeichen neben Blizzards Quest-Symbolen, bei jedem Zoom gleich gross.
- **Automatisches Verfolgen** des nächsten Orts (Quest oder Kartenmarkierung).
- **Deutsch und Englisch** – richtet sich nach der Client-Sprache.

### Installation

1. Repository herunterladen (*Code → Download ZIP*) und den Ordner **`Wegweiser`** nach
   `World of Warcraft/<Forever-Client-Ordner>/Interface/AddOns/` kopieren.
   Tipp: In der CurseForge-App per Rechtsklick auf ein installiertes Addon den Ordner öffnen, dann hast du den richtigen Pfad.
2. **Optional, empfohlen:** **QuestieDB** für Vorschläge und Gebietsüberschneidung installieren.
   Es kommt mit [Questie](https://www.curseforge.com/wow/addons/questie) über CurseForge.
   Wer Questie selbst nicht will: in der Addon-Liste *Questie* aus- und *QuestieDB* eingeschaltet lassen – QuestieDB hat keine eigene Oberfläche.
3. Falls das Addon ausgegraut ist: *Veraltete AddOns laden* anhaken.

Ohne QuestieDB sortiert Wegweiser trotzdem die Quests in deinem Log – nur ohne Vorschläge und Gebietshinweise.

### Bedienung

| Aktion | Wirkung |
|---|---|
| Klick auf eine Zeile | diesen Ort verfolgen |
| Shift-Klick | als Nächstes festnageln (nochmals: aufheben) |
| Strg-Klick | auf später parken (nochmals: wieder einplanen) |
| Rechtsklick | Vorschlag ausblenden |
| Pfeil-Knopf | sofort neu berechnen |
| Zahnrad | Einstellungen und Legende aller Bedienelemente |

**Befehle:** `/ww` Panel ein/aus · `/ww optionen` · `/ww neu` · `/ww track` · `/ww pins` · `/ww suggest` · `/ww grey` · `/ww unignore` · `/ww unpark` · `/ww reset`

Die Einstellungen gibt es auch unter *Esc → Optionen → AddOns → Wegweiser*.

### Grenzen

- Geplant wird innerhalb der aktuellen Zone (noch ohne Flugpunkte).
- Questketten werden nicht automatisch vorausgeplant – Wegweiser weist darauf hin, du entscheidest (festnageln / parken).
- Die Datenqualität für neue Forever-Inhalte hängt von QuestieDB ab, das fast täglich aktualisiert wird.

### Lizenz

Wegweiser steht unter der [MIT-Lizenz](LICENSE). Questdaten stammen zur Laufzeit aus [QuestieDB](https://github.com/Questie/QuestieDB) (optionale Abhängigkeit); Wegweiser enthält keinen Code und keine Daten von Questie.
