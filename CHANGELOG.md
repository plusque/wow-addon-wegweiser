# Changelog

## 0.6.3 – 2026-11-22
- **Quest givers in tooltips:** suggestions to accept now show who gives the quest – name and title (e.g. "from Ragnar Thunderbrew <Innkeeper>") or the object (e.g. a wanted poster)
- Quest givers that walk around are marked "walks around", and their path is drawn as small blue dots on the world map; givers with several locations show how many there are
- **Target button** (circle icon in the panel header): targets the next quest giver of your route and marks them with a circle – handy in crowded towns, inns and buildings. Works within sight; also available as a key binding (Keybindings > AddOns > Wegweiser)
- Quest givers with many spawn points: the nearest one is now found among up to 40 instead of 6

## 0.6.2 – 2026-11-22
- **Quest log aware routes:** the route keeps track of your quest log along the way – a turn-in frees a slot, accepting takes one. Suggestions to accept are only scheduled while there is room, and if a slot only opens up after a turn-in, they come after it
- If there are more suggestions than room, the ones that matter most are kept: pinned first, then quests with objectives where your route goes anyway, then the closest ones; quests that are too hard come last
- Suggestions without room go to the end of the route, marked "[no room]"; the footer shows e.g. "Quest log 23/25: 6 suggestions waiting for room"
- New setting "Keep slots free" (default 2) for quests that start from loot or escort NPCs; also `/ww reserve 0-10`, `/ww log` shows the current state

## 0.6.1 – 2026-11-07
- Quest level shown in difficulty colours (red, orange, yellow, green, grey) in the panel and tooltips
- Suggested quests 3 or more levels above you are no longer scheduled early: they go to the end of the route, marked "[too hard]"
- New setting "Hide quests that are too hard" to leave them out entirely

## 0.6.0 – 2026-11-06
- **Range setting** (settings window or `/ww range 0-2`):
  - 0 – current zone only (as before, default)
  - 1 – show other zones: zones with quests in your log plus up to three nearby zones that suit your level, one row each with a tooltip listing their route
  - 2 – one route across zone borders on foot, based on world coordinates; zone changes are marked in the panel, map numbers appear in every zone of the route
- Quests whose giver is in another zone of the route are now accepted beforehand instead of being listed under "Pick up first in …"
- Distances in the panel are measured in world coordinates

## 0.5.2 – 2026-10-19
- Recalculate button gives visible feedback: the panel flashes briefly and the header shows "recalculated ✓" with the number of stops for about two seconds

## 0.5.1 – 2026-10-19
- Learns from quest givers: when you talk to an NPC, quests it does not actually offer are no longer suggested. Works around gaps in QuestieDB for new Forever quests (e.g. "Stormy Potential" at Rezlak, whose prerequisite is missing in QuestieDB 1.0.6). Cleared on level-up, after turning in a prerequisite, or via the settings window

## 0.5.0 – 2026-10-18
- German and English interface, following the client language

## 0.4.0 – 2026-10-18
- Area overlap: quests with objectives at the same place are accepted beforehand (same zone), listed under "Pick up first in …" (other zone) or flagged with "!" (available soon)
- Profession quests are suggested when you have the profession

## 0.3.0 – 2026-10-18
- Shift-click pins a stop as next, ctrl-click parks it for later
- Settings window (gear button, `/ww options`, Esc → Options → AddOns) with a legend of all controls

## 0.2.0 – 2026-10-18
- Suggestions for quests you can accept in the zone (via QuestieDB, optional)
- Recalculate button and automatic second pass after accepting quests
- Accept stops are preferred early in the route

## 0.1.1 – 2026-10-18
- World map numbers as badges next to Blizzard's quest icons, fixed size at every zoom level

## 0.1.0 – 2026-10-18
- First version: route panel, auto-tracking, world map numbers
