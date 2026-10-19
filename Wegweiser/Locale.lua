-- Wegweiser: Sprachen. Deutsch ist der Grundtext; bei jedem anderen Client gilt Englisch.
-- Nutzung: L["deutscher Text"] liefert die passende Übersetzung (oder den deutschen Text).

local _, ns = ...

local EN = {
  -- Panel
  ["Route neu berechnen"] = "Recalculate route",
  ["Einstellungen und Bedienung"] = "Settings and controls",
  ["Ort %d"] = "Stop %d",
  ["Wegweiser: Ort "] = "Wegweiser: stop ",
  ["Abgeben:"] = "Turn in:",
  ["Abgeben: "] = "Turn in: ",
  ["Abgeben (beim Questgeber?): "] = "Turn in (at quest giver?): ",
  ["Annehmen:"] = "Accept:",
  ["Annehmen: "] = "Accept: ",
  ["Stufe "] = "Level ",
  ["Ziele"] = "objectives",
  ["Hier gleich mit erledigen:"] = "Do these here as well:",
  [" (wird vorher angenommen)"] = " (accepted beforehand)",
  ["Kommt später nochmal hierher:"] = "You will come back here later for:",
  ["Tipp: Strg-Klick parkt diesen Ort, bis du alles zusammen erledigen kannst."] =
    "Tip: Ctrl-click parks this stop until you can do everything at once.",
  ["Klick: diesen Ort verfolgen"] = "Click: track this stop",
  ["Shift-Klick: Festnageln aufheben"] = "Shift-click: unpin",
  ["Shift-Klick: als Nächstes festnageln"] = "Shift-click: pin as next stop",
  ["Strg-Klick: wieder einplanen"] = "Ctrl-click: schedule again",
  ["Strg-Klick: auf später parken"] = "Ctrl-click: park for later",
  ["Rechtsklick: Vorschlag ausblenden"] = "Right-click: hide suggestion",
  ["Rechtsklick: ausblenden"] = "Right-click: hide",
  ["[später]"] = "[later]",
  ["[fix]"] = "[pin]",
  ["Vorher holen in"] = "Pick up first in",
  ["Quest"] = "quest",
  ["Quests"] = "quests",
  ["Diese Quests haben ihre Ziele an Orten deiner Route."] = "These quests have objectives at stops on your route.",
  ["  gleiches Gebiet wie: "] = "  same area as: ",
  ["Keine Quests in dieser Zone."] = "No quests in this zone.",
  [" weitere Orte"] = " more stops",
  [" Quest(s) in anderen Zonen"] = " quest(s) in other zones",
  ["Vorschläge: QuestieDB nicht installiert"] = "Suggestions: QuestieDB not installed",
  ["Vorschläge: QuestieDB zu alt"] = "Suggestions: QuestieDB too old",
  ["Vorschläge werden geladen ..."] = "Loading suggestions ...",
  ["Vorschläge: Fehler beim Laden"] = "Suggestions: error while loading",

  -- Meldungen
  [" Vorschlag/Vorschläge ausgeblendet. Zurücksetzen mit /ww unignore"] =
    " suggestion(s) hidden. Undo with /ww unignore",
  ["Ausgeblendet. Zurücksetzen mit /ww unignore oder in den Einstellungen."] =
    "Hidden. Undo with /ww unignore or in the settings.",
  ["Festnageln aufgehoben."] = "Unpinned.",
  ["Als Nächstes festgenagelt: "] = "Pinned as next stop: ",
  ["Auf später geparkt."] = "Parked for later.",
  ["Wieder eingeplant."] = "Scheduled again.",
  ["Route neu berechnet."] = "Route recalculated.",
  ["Alle ausgeblendeten Vorschläge werden wieder angezeigt."] = "All hidden suggestions are shown again.",
  ["Alle geparkten Quests sind wieder eingeplant."] = "All parked quests are scheduled again.",
  ["an"] = "on",
  ["aus"] = "off",
  ["Nächsten Ort automatisch verfolgen"] = "Automatically track the next stop",
  ["Nummern auf der Weltkarte"] = "Numbers on the world map",
  ["Vorschläge zum Annehmen"] = "Suggestions to accept",
  ["Graue Quests vorschlagen"] = "Suggest grey quests",

  -- Verfügbarkeit
  ["ab Stufe "] = "from level ",
  ["nach"] = "after",

  -- Einstellungsfenster
  ["Wegweiser - Einstellungen"] = "Wegweiser - Settings",
  ["Anzeige"] = "Display",
  ["Zurücksetzen"] = "Reset",
  ["Bedienung im Panel"] = "Panel controls",
  ["Panel anzeigen"] = "Show panel",
  ["Setzt die Quest bzw. eine Kartenmarkierung für Ort 1."] = "Tracks the quest or sets a map pin for stop 1.",
  ["Benötigt das Addon QuestieDB."] = "Requires the QuestieDB addon.",
  ["Auch graue (zu tiefe) Quests vorschlagen"] = "Also suggest grey (low-level) quests",
  ["QuestieDB nicht installiert"] = "QuestieDB not installed",
  ["QuestieDB zu alt"] = "QuestieDB too old",
  ["wird geladen ..."] = "loading ...",
  ["bereit"] = "ready",
  ["Fehler beim Laden"] = "error while loading",
  ["Ausgeblendete Vorschläge zeigen (%d)"] = "Show hidden suggestions (%d)",
  ["Geparkte Quests einplanen (%d)"] = "Schedule parked quests (%d)",
  ["Am Questgeber gelernte Sperren löschen (%d)"] = "Clear quests learned as unavailable (%d)",
  ["Panel-Position zurücksetzen"] = "Reset panel position",
  ["Einstellungen öffnen"] = "Open settings",
  ["Klick"] = "Click",
  ["Ort verfolgen"] = "track stop",
  ["Shift-Klick"] = "Shift-click",
  ["als Nächstes festnageln (nochmals: aufheben)"] = "pin as next stop (again: unpin)",
  ["Strg-Klick"] = "Ctrl-click",
  ["auf später parken (nochmals: wieder einplanen)"] = "park for later (again: schedule again)",
  ["Rechtsklick"] = "Right-click",
  ["Vorschlag ausblenden"] = "hide suggestion",
  ["Pfeil-Knopf"] = "Arrow button",
  ["Route sofort neu berechnen"] = "recalculate route now",
  ["im Panel"] = "in panel",
  ["Ort kommt später nochmal (Grund im Tooltip)"] = "you will return here later (reason in tooltip)",
  ["andere Quest hier gleich miterledigen"] = "do another quest here as well",
  ["Vorher holen"] = "Pick up first",
  ["Quests aus anderen Zonen für deine Route"] = "quests from other zones for your route",
  ["Panel ziehen"] = "Drag panel",
  ["verschieben"] = "move it",
  ["/ww  Panel ein/aus   ·   /ww optionen   ·   /ww neu"] = "/ww  toggle panel   ·   /ww options   ·   /ww refresh",
}

local useEnglish = (GetLocale and GetLocale() or "enUS") ~= "deDE"

ns.L = setmetatable({}, {
  __index = function(_, key)
    if useEnglish and EN[key] then return EN[key] end
    return key
  end,
})
ns.isEnglish = useEnglish
