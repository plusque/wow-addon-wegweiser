-- Wegweiser: Wissen aus QuestieDB (optionale Abhängigkeit, öffentliche API für Fremd-Addons).
--  * Vorschläge: Quests, die man in der Zone annehmen kann
--  * Gebietsüberschneidung: welche anderen Quests haben ihre Ziele am selben Ort?
-- Ohne QuestieDB bleibt Wegweiser voll nutzbar, nur ohne diese Extras.

local _, ns = ...
local L = ns.L
local S = {}
ns.Suggest = S

S.state = "off"          -- off | missing | outdated | indexing | ready | error
local zoneIndex = {}     -- uiMapID -> { [questID] = { {x, y}, ... } }   Questgeber-Orte (0-1)
local objIndex = {}      -- uiMapID -> { [questID] = { n = total, x1, y1, x2, y2, ... } } Zielpunkte
local starter = {}       -- questID -> { kind = 1|2, id = npc/objectID, maps = { [uiMapID] = true } }
local byNpc = {}         -- npcID -> { [questID] = true }  Quests, die dieser NPC laut DB vergibt
local static = {}        -- questID -> zwischengespeicherte Felder
local areaToUi = {}
local npcCache, objCache, dropCache = {}, {}, {}

-- Feiertags- und Event-Quests (QuestSort-IDs aus QuestieDB) nie vorschlagen
local EVENT_SORTS = {
  [-404] = true, [-402] = true, [-378] = true, [-376] = true, [-375] = true, [-374] = true,
  [-370] = true, [-369] = true, [-366] = true, [-364] = true, [-41] = true, [-22] = true,
  [-21] = true, [-1000] = true,
}
local MAX_POINTS = 6       -- Spawnpunkte pro Questgeber
local MAX_OBJ_SAMPLES = 24 -- Zielpunkte pro Quest und Karte (gleichmässig ausgedünnt)
local MAX_DROPPERS = 20    -- Beute, die mehr Gegner fallen lassen, gilt als zu allgemein
local LOOKAHEAD_LEVELS = 2 -- «kommt später nochmal»: bis so viele Stufen voraus

local function safe(fn, ...)
  if not fn then return nil end
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
end

-- Masken können > 32 Bit sein (Forever-Rassen), daher ohne bit-Bibliothek prüfen
local function hasBit(mask, bitval)
  return math.floor(mask / bitval) % 2 == 1
end

local function decodeMap(value)
  if type(value) == "string" then
    local fn = loadstring(value)
    return fn and fn() or {}
  end
  return type(value) == "table" and value or {}
end

local function spawnsOf(kind, id)
  local cache = kind == 1 and npcCache or objCache
  local v = cache[id]
  if v == nil then
    v = safe(kind == 1 and NpcDB.spawns or ObjectDB.spawns, id) or false
    cache[id] = v
  end
  return v or nil
end

local function dropsOf(itemId)
  local v = dropCache[itemId]
  if v == nil then
    v = { n = safe(ItemDB.npcDrops, itemId) or {}, o = safe(ItemDB.objectDrops, itemId) or {} }
    dropCache[itemId] = v
  end
  return v
end

------------------------------------------------------------------------
-- Initialisierung
------------------------------------------------------------------------
function S.Init()
  if S.state ~= "off" then return end
  if not (LibQuestieDB and QuestDB and NpcDB and ObjectDB and ItemDB) then S.state = "missing" return end
  if LibQuestieDB.RequireContract then
    local ok = LibQuestieDB.RequireContract(3)
    if not ok then S.state = "outdated" return end
  end

  -- Deutsche Quest- und NPC-Namen, falls der Client deutsch ist
  local loc = GetLocale and GetLocale()
  local l10n = LibQuestieDB.l10n
  if loc and loc ~= "enUS" and loc ~= "enGB" and l10n and l10n.SetLocale and l10n.currentLocale ~= loc then
    safe(l10n.SetLocale, loc)
  end

  local zdb = LibQuestieDB.Support and safe(LibQuestieDB.Support.Get, "ZoneDB")
  local priv = zdb and zdb.private or {}
  areaToUi = decodeMap(priv.areaIdToUiMapId)
  for k, v in pairs(decodeMap(priv.areaIdToUiMapIdOverride)) do areaToUi[k] = v end

  S.state = "indexing"
  S.co = coroutine.create(S.BuildIndex)
end

-- Questgeber einer Quest erfassen
local function indexStarter(q)
  local sb = safe(QuestDB.startedBy, q)
  if not sb then return end
  for kind = 1, 2 do                      -- 1 = NPCs, 2 = Objekte (Items separat)
    for _, id in ipairs(sb[kind] or {}) do
      for areaId, coords in pairs(spawnsOf(kind, id) or {}) do
        local ui = areaToUi[areaId]
        if ui and ui ~= 0 then
          local zone = zoneIndex[ui]
          if not zone then zone = {}; zoneIndex[ui] = zone end
          local pts = zone[q]
          if not pts then pts = {}; zone[q] = pts end
          for _, c in ipairs(coords) do
            if #pts >= MAX_POINTS then break end
            local x, y = c[1], c[2]
            if x and y and x >= 0 and y >= 0 then pts[#pts + 1] = { x / 100, y / 100 } end
          end
          if #pts == 0 then
            zone[q] = nil
          else
            local st = starter[q]
            if not st then st = { kind = kind, id = id, maps = {} }; starter[q] = st end
            if kind == 1 then
              byNpc[id] = byNpc[id] or {}
              byNpc[id][q] = true
            end
            st.maps[ui] = true
          end
        end
      end
    end
  end
  if sb[3] and #sb[3] > 0 then
    starter[q] = starter[q] or { maps = {} }
    starter[q].byItem = true
  end
end

-- Zielorte einer Quest erfassen: Gegner, Objekte, Beute-Quellen, Kill-Credit, Trigger
local function indexObjectives(q)
  local per = {}
  local function add(spawns)
    for areaId, coords in pairs(spawns or {}) do
      local ui = areaToUi[areaId]
      if ui and ui ~= 0 then
        local l = per[ui]
        if not l then l = {}; per[ui] = l end
        for _, c in ipairs(coords) do
          local x, y = c[1], c[2]
          if x and y and x >= 0 and y >= 0 then l[#l + 1] = x / 100; l[#l + 1] = y / 100 end
        end
      end
    end
  end
  local obj = safe(QuestDB.objectives, q)
  if obj then
    for _, c in ipairs(obj[1] or {}) do add(spawnsOf(1, c[1])) end
    for _, c in ipairs(obj[2] or {}) do add(spawnsOf(2, c[1])) end
    for _, c in ipairs(obj[3] or {}) do
      local d = dropsOf(c[1])
      if #d.n <= MAX_DROPPERS then for _, id in ipairs(d.n) do add(spawnsOf(1, id)) end end
      if #d.o <= MAX_DROPPERS then for _, id in ipairs(d.o) do add(spawnsOf(2, id)) end end
    end
    for _, kc in ipairs(obj[5] or {}) do
      for _, id in ipairs(type(kc[1]) == "table" and kc[1] or {}) do add(spawnsOf(1, id)) end
    end
  end
  local te = safe(QuestDB.triggerEnd, q)
  if te and type(te[2]) == "table" then add(te[2]) end

  for ui, l in pairs(per) do
    local n = #l / 2
    if n > 0 then
      local stride = math.max(1, math.ceil(n / MAX_OBJ_SAMPLES))
      local s = { n = n }
      for i = 1, n, stride do s[#s + 1] = l[2 * i - 1]; s[#s + 1] = l[2 * i] end
      local zone = objIndex[ui]
      if not zone then zone = {}; objIndex[ui] = zone end
      zone[q] = s
    end
  end
end

-- Einmaliger Durchlauf über alle Quests (im Hintergrund, verteilt auf viele Frames)
function S.BuildIndex()
  local ids = QuestDB.GetAllIds() or {}
  for i, q in ipairs(ids) do
    indexStarter(q)
    indexObjectives(q)
    if i % 25 == 0 then coroutine.yield() end
  end
  S.state = "ready"
end

-- Index schrittweise aufbauen, damit das Spiel nicht ruckelt (max. ~5 ms pro Frame)
function S.Step()
  if S.state ~= "indexing" or not S.co then return false end
  local start = debugprofilestop and debugprofilestop()
  repeat
    local ok, err = coroutine.resume(S.co)
    if not ok then S.state = "error"; S.err = err; return false end
    if coroutine.status(S.co) == "dead" then S.co = nil; return true end
  until not start or debugprofilestop() - start > 5
  return false
end

------------------------------------------------------------------------
-- Verfügbarkeit
------------------------------------------------------------------------
local function staticOf(q)
  local s = static[q]
  if s then return s end
  local G = function(k) return safe(QuestDB.Get, q, k) end
  local blocked = false
  for _, k in ipairs({ "requiredMinRep", "requiredMaxRep", "requiredSourceItems", "requiredRanks" }) do
    if G(k) ~= nil then blocked = true end
  end
  for _, k in ipairs({ "requiredSpell", "requiredSpecialization" }) do
    local v = G(k)
    if v and v ~= 0 then blocked = true end
  end
  local sort = G("zoneOrSort") or 0
  if EVENT_SORTS[sort] then blocked = true end
  local sf = G("specialFlags") or 0
  if sf ~= 0 and hasBit(sf, 1) then blocked = true end      -- wiederholbar: keine Route nötig
  s = {
    blocked = blocked,
    rl = G("requiredLevel") or 0, ql = G("questLevel") or 0, maxl = G("requiredMaxLevel") or 0,
    rr = G("requiredRaces") or 0, rc = G("requiredClasses") or 0,
    skill = G("requiredSkill"),
    pg = G("preQuestGroup"), ps = G("preQuestSingle"), ex = G("exclusiveTo"),
    nxt = G("nextQuestInChain") or 0, bc = G("breadcrumbForQuestId") or 0,
    parent = G("parentQuest") or 0, auc = G("availableUntilCompleted") or 0,
    asw = G("availableStartingWith") or 0, dbq = G("disabledByQuest") or 0,
  }
  static[q] = s
  return s
end

-- Ab welchem Abstand gilt eine Quest als grau (Classic-Faustregel)
local function trivialRange(level)
  if level <= 9 then return 4 elseif level <= 19 then return 5
  elseif level <= 29 then return 6 elseif level <= 39 then return 7 end
  return 8
end

local function done(q) return q and q ~= 0 and safe(C_QuestLog.IsQuestFlaggedCompleted, q) end
local function active(q)
  local idx = q and q ~= 0 and safe(C_QuestLog.GetLogIndexForQuestID, q)
  return idx and idx > 0
end

-- Prüft eine Quest. Rückgabe:
--   "ok"                    jetzt annehmbar
--   "soon", Grund           bald annehmbar (Vorquest erreichbar oder bis +2 Stufen)
--   nil                     nicht (absehbar) verfügbar
-- wantSoon = false bricht beim ersten Hindernis ab (schneller).
function S.Check(q, ctx, wantSoon)
  local cache = ctx.cache
  local key = wantSoon and q or -q
  if cache and cache[key] ~= nil then
    local c = cache[key]
    return c[1] or nil, c[2]
  end
  local function finish(a, b)
    if cache then cache[key] = { a or false, b } end
    return a or nil, b
  end

  if active(q) or done(q) then return finish(nil) end
  local s = staticOf(q)
  if s.blocked then return finish(nil) end
  -- Am Questgeber selbst festgestellt: wird (noch) nicht angeboten
  if ctx.unavailable and ctx.unavailable[q] then return finish(nil) end
  if s.maxl ~= 0 and ctx.level > s.maxl then return finish(nil) end
  if not ctx.showGrey and s.ql > 0 and ctx.level - s.ql > trivialRange(ctx.level) then return finish(nil) end
  if s.rr ~= 0 and ctx.raceBit and not hasBit(s.rr, ctx.raceBit) then return finish(nil) end
  if s.rc ~= 0 and ctx.classBit and not hasBit(s.rc, ctx.classBit) then return finish(nil) end
  if s.skill then
    local have = ctx.skills[s.skill[1]]
    if not have or have < (s.skill[2] or 1) then return finish(nil) end
  end
  if s.ex then for _, p in ipairs(s.ex) do if done(p) or active(p) then return finish(nil) end end end
  if s.nxt ~= 0 and (done(s.nxt) or active(s.nxt)) then return finish(nil) end
  if s.bc ~= 0 and (done(s.bc) or active(s.bc)) then return finish(nil) end
  if s.parent ~= 0 and not active(s.parent) then return finish(nil) end
  if s.auc ~= 0 and done(s.auc) then return finish(nil) end
  if s.asw ~= 0 and not (done(s.asw) or active(s.asw)) then return finish(nil) end
  if s.dbq ~= 0 and active(s.dbq) then return finish(nil) end

  local reasons = {}
  if s.rl > ctx.level then
    if not wantSoon or s.rl > ctx.level + LOOKAHEAD_LEVELS then return finish(nil) end
    reasons[#reasons + 1] = L["ab Stufe "] .. s.rl
  end

  -- Eine fehlende Vorquest gilt als «erreichbar», wenn sie im Log ist, jetzt annehmbar ist
  -- oder über Beute startet.
  local function reachable(p)
    if active(p) then return true end
    local st = starter[p]
    if st and st.byItem then return true end
    return S.Check(p, ctx, false) == "ok"
  end
  if s.pg then
    for _, p in ipairs(s.pg) do
      if not done(p) then
        if not wantSoon or not reachable(p) then return finish(nil) end
        reasons[#reasons + 1] = L["nach"] .. " «" .. (S.Name(p) or ("Quest " .. p)) .. "»"
      end
    end
  end
  if s.ps then
    local any, via = false, nil
    for _, p in ipairs(s.ps) do
      if done(p) then any = true break end
      if not via and wantSoon and reachable(p) then via = p end
    end
    if not any then
      if not via then return finish(nil) end
      reasons[#reasons + 1] = L["nach"] .. " «" .. (S.Name(via) or ("Quest " .. via)) .. "»"
    end
  end

  if #reasons > 0 then return finish("soon", table.concat(reasons, ", ")) end
  return finish("ok")
end

function S.IsAvailable(q, ctx) return S.Check(q, ctx, false) == "ok" end

function S.PlayerContext(showGrey)
  local _, _, raceId = UnitRace("player")
  local _, _, classId = UnitClass("player")
  local raceBit = raceId and LibQuestieDB.Enum and LibQuestieDB.Enum.raceMaskById
    and LibQuestieDB.Enum.raceMaskById[raceId]
  return {
    level = UnitLevel("player") or 1,
    raceBit = raceBit,
    classBit = classId and 2 ^ (classId - 1),
    skills = S.PlayerSkills(),
    showGrey = showGrey,
    cache = {},
  }
end

-- Berufe des Spielers: { [skillLineID] = Skill }. Ohne passende API bleibt die Liste leer,
-- dann werden Berufsquests (wie bisher) nicht vorgeschlagen.
function S.PlayerSkills()
  local res = {}
  if GetProfessions and GetProfessionInfo then
    local ok, p1, p2, p3, p4, p5, p6 = pcall(GetProfessions)
    if ok then
      for _, idx in pairs({ p1, p2, p3, p4, p5, p6 }) do
        local ok2, _, _, rank, _, _, _, skillLine = pcall(GetProfessionInfo, idx)
        if ok2 and skillLine then res[skillLine] = rank or 0 end
      end
    end
  end
  return res
end

-- Verfügbare Quests mit Questgeber auf dieser Karte: { {q=, x=, y=}, ... }, jeweils nächster Spawn
function S.ForMap(uiMapID, px, py, ignored, ctx)
  local res = {}
  if S.state ~= "ready" then return res end
  local zone = zoneIndex[uiMapID]
  if not zone then return res end
  for q, pts in pairs(zone) do
    if not (ignored and ignored[q]) and S.IsAvailable(q, ctx) then
      local best, bd
      for _, p in ipairs(pts) do
        local dx, dy = p[1] - (px or 0.5), p[2] - (py or 0.5)
        local d = dx * dx + dy * dy
        if not bd or d < bd then best, bd = p, d end
      end
      res[#res + 1] = { q = q, x = best[1], y = best[2] }
    end
  end
  return res
end

------------------------------------------------------------------------
-- Gebietsüberschneidung
------------------------------------------------------------------------
-- Welche anderen Quests haben ihre Ziele rund um (x, y)?
--   isNear(x1, y1, x2, y2) entscheidet über die Nähe (Distanzrechnung liegt im Hauptmodul)
-- Rückgabe: { now = {q,...}, elsewhere = {q,...}, later = { {q=, why=}, ... } }
--   now        jetzt annehmbar, Questgeber auf dieser Karte  -> vorher einplanen
--   elsewhere  jetzt annehmbar, Questgeber woanders          -> «Vorher holen in ...»
--   later      bald annehmbar                                 -> «kommt später nochmal»
function S.Related(uiMapID, x, y, isNear, ctx, ignored, exclude)
  local res = { now = {}, elsewhere = {}, later = {} }
  if S.state ~= "ready" then return res end
  local zone = objIndex[uiMapID]
  if not zone then return res end
  for q, s in pairs(zone) do
    if q ~= exclude and not (ignored and ignored[q]) then
      local samples = #s / 2
      local near = 0
      for i = 1, #s, 2 do
        if isNear(s[i], s[i + 1], x, y) then near = near + 1 end
      end
      -- Gleiches Gebiet: ein spürbarer Teil der Zielorte liegt im Umkreis. Verstreute Ziele
      -- (z.B. Eier entlang einer Küste) zählen ab 3 Fundorten und 20 %, kompakte ab 2 und 30 %.
      local ratio = near / samples
      if (near >= 3 and ratio >= 0.2) or (near >= 2 and ratio >= 0.3) then
        local status, why = S.Check(q, ctx, true)
        if status == "ok" then
          local st = starter[q]
          if st and st.maps[uiMapID] then
            res.now[#res.now + 1] = q
          elseif st and next(st.maps) then
            res.elsewhere[#res.elsewhere + 1] = q
          end
        elseif status == "soon" then
          res.later[#res.later + 1] = { q = q, why = why }
        end
      end
    end
  end
  return res
end

-- Wo und bei wem holt man eine Quest? Liefert Kartenname, Karten-ID und Questgeber-Name.
function S.StarterInfo(q, preferNot)
  local st = starter[q]
  if not st then return nil end
  local ui
  for m in pairs(st.maps) do
    if m ~= preferNot then ui = m break end
  end
  ui = ui or next(st.maps)
  local mapName = ui and C_Map and C_Map.GetMapInfo and (safe(C_Map.GetMapInfo, ui) or {}).name
  local who
  if st.kind == 1 then who = safe(NpcDB.name, st.id)
  elseif st.kind == 2 then who = safe(ObjectDB.name, st.id) end
  return mapName or "?", ui, who
end

-- Quests, die dieser NPC laut Datenbank vergibt
function S.QuestsOfNpc(npcId)
  return byNpc[npcId]
end

-- Vorquests laut Datenbank (für das Zurücksetzen gelernter Sperren)
function S.Prereqs(q)
  local s = staticOf(q)
  return s.pg, s.ps
end

function S.Name(q)
  return safe(QuestDB.name, q)
end

function S.Level(q)
  local s = staticOf(q)
  return s.ql
end
