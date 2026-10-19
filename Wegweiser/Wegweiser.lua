-- Wegweiser 0.5.2
-- Ordnet die Quests im Log, die in der aktuellen Zone liegen, zu einer kurzen Route:
-- Orte werden gebuendelt, jeder Ort nur einmal angelaufen. Mit QuestieDB kommen
-- Vorschläge für Quests dazu, die man in der Zone noch annehmen kann.
--
-- Befehle:
--   /ww            Panel ein-/ausblenden
--   /ww track      Automatisches Verfolgen des nächsten Orts an/aus
--   /ww pins       Nummern auf der Weltkarte an/aus
--   /ww suggest    Vorschläge (Annehmen) an/aus
--   /ww grey       Auch graue (zu tiefe) Quests vorschlagen an/aus
--   /ww neu        Route sofort neu berechnen (auch Knopf im Panel)
--   /ww unignore   Ausgeblendete Vorschläge wieder anzeigen
--   /ww reset      Panel-Position zurücksetzen

local ADDON_NAME, ns = ...
local L = ns.L
local DB

local CLUSTER_RADIUS = 60      -- Yards: Punkte naeher als das gelten als ein Ort
local YARD_TO_M = 0.9144
local MAX_ROWS = 12            -- mehr Orte zeigt das Panel nicht an
local ACCEPT_WEIGHT = 0.6      -- wie stark spaetes Annehmen bestraft wird
local RELATED_RADIUS = 250     -- Yards: Ziele so nah gelten als «gleiches Gebiet»
local COLOR_NEXT = "|cffffd100"
local COLOR_DONE = "|cff40ff40"
local COLOR_ACCEPT = "|cff66bbff"
local COLOR_LATER = "|cffff9900"
local fetchRows, getFetchRow   -- «Vorher holen»-Zeilen, weiter unten definiert
local COLOR_DIM  = "|cff9d9d9d"

local route = {}               -- aktuelle Route: Liste von Orten
local routeMapID
local otherZoneCount = 0
local preFetch = {}            -- Kartenname -> { {q=, who=, forQ=}, ... }  «Vorher holen in ...»
local lastTracked

------------------------------------------------------------------------
-- Hilfsfunktionen
------------------------------------------------------------------------
local function msg(text) print("|cff66ccffWegweiser|r " .. text) end

local function safe(fn, ...)
  if not fn then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
end

local function playerPos()
  local m = safe(C_Map.GetBestMapForUnit, "player")
  if not m then return nil end
  local p = safe(C_Map.GetPlayerMapPosition, m, "player")
  if not p then return m end
  local x, y = p:GetXY()
  return m, x, y
end

local sizeCache = {}
local function mapSize(m)
  if sizeCache[m] then return sizeCache[m][1], sizeCache[m][2] end
  local w, h = safe(C_Map.GetMapWorldSize, m)
  if not (w and w > 0) and C_Map.GetWorldPosFromMapPos and CreateVector2D then
    local _, a = safe(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(0, 0))
    local _, b = safe(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(1, 1))
    if a and b then
      local ax, ay = a:GetXY()
      local bx, by = b:GetXY()
      w, h = math.abs(ay - by), math.abs(ax - bx)
    end
  end
  if not (w and w > 0) then w, h = 1000, 1000 end
  sizeCache[m] = { w, h }
  return w, h
end

-- Distanz in Yards zwischen zwei Kartenpunkten derselben Karte
local function dist(m, x1, y1, x2, y2)
  local w, h = mapSize(m)
  local dx, dy = (x1 - x2) * w, (y1 - y2) * h
  return math.sqrt(dx * dx + dy * dy)
end

local function inLog(q)
  local idx = safe(C_QuestLog.GetLogIndexForQuestID, q)
  return idx and idx > 0
end

local function isReady(q)
  if safe(C_QuestLog.ReadyForTurnIn, q) then return true end
  return safe(C_QuestLog.IsComplete, q) and true or false
end

local function title(q)
  return safe(C_QuestLog.GetTitleForQuestID, q)
    or (ns.Suggest and ns.Suggest.state == "ready" and ns.Suggest.Name(q))
    or ("Quest " .. q)
end

-- Nächsten Ort verfolgen: Quest im Log per Super-Tracking, sonst Kartenmarkierung
local function trackStop(stop, mapID)
  if not stop then return end
  for _, it in ipairs(stop.items) do
    if not it.accept then
      safe(C_Map.ClearUserWaypoint)
      safe(C_SuperTrack.SetSuperTrackedQuestID, it.q)
      return
    end
  end
  if UiMapPoint and UiMapPoint.CreateFromCoordinates and mapID then
    local point = safe(UiMapPoint.CreateFromCoordinates, mapID, stop.x, stop.y)
    if point then
      safe(C_Map.SetUserWaypoint, point)
      safe(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
  end
end

local function progress(q)
  local objs = safe(C_QuestLog.GetQuestObjectives, q)
  if not objs or #objs == 0 then return "" end
  if #objs == 1 and objs[1].numRequired and objs[1].numRequired > 1 then
    return string.format("%d/%d", objs[1].numFulfilled or 0, objs[1].numRequired)
  end
  local done = 0
  for _, o in ipairs(objs) do if o.finished then done = done + 1 end end
  return string.format("%d/%d %s", done, #objs, L["Ziele"])
end

------------------------------------------------------------------------
-- Lernen: wo werden Quests angenommen und abgegeben?
------------------------------------------------------------------------
local function remember(store, q)
  local m, x, y = playerPos()
  if q and m and x then DB[store][q] = { m = m, x = x, y = y } end
end

------------------------------------------------------------------------
-- Route berechnen
------------------------------------------------------------------------
local function collectPoints(m)
  local pts, seen = {}, {}
  for _, e in ipairs(safe(C_QuestLog.GetQuestsOnMap, m) or {}) do
    local q = e.questID
    if q and e.x and e.y and not seen[q] and inLog(q) then
      seen[q] = true
      pts[#pts + 1] = { q = q, x = e.x, y = e.y, ready = isReady(q) }
    end
  end
  -- Fertige Quests ohne Kartenpunkt: Abgabe vermutlich beim Questgeber
  local others = 0
  local n = safe(C_QuestLog.GetNumQuestLogEntries) or 0
  for i = 1, n do
    local info = safe(C_QuestLog.GetInfo, i)
    if info and not info.isHeader and info.questID and not seen[info.questID] and not info.isHidden then
      local q = info.questID
      local p = DB.pickups[q]
      if isReady(q) and p and p.m == m then
        seen[q] = true
        pts[#pts + 1] = { q = q, x = p.x, y = p.y, ready = true, guess = true }
      else
        others = others + 1
      end
    end
  end
  -- Vorschläge: Quests, die man in dieser Zone noch annehmen kann
  local S = ns.Suggest
  preFetch = {}
  if DB.suggest and S and S.state == "ready" then
    local ctx = S.PlayerContext(DB.grey)
    ctx.unavailable = DB.unavailable
    local _, px, py = playerPos()
    for _, s in ipairs(S.ForMap(m, px, py, DB.ignored, ctx)) do
      if not seen[s.q] then
        seen[s.q] = true
        pts[#pts + 1] = { q = s.q, x = s.x, y = s.y, accept = true }
      end
    end

    -- Gebietsüberschneidung: welche anderen Quests haben ihre Ziele dort, wo eine Quest
    -- aus dem Log hinführt?
    local function isNear(x1, y1, x2, y2) return dist(m, x1, y1, x2, y2) <= RELATED_RADIUS end
    local fetchSeen = {}
    for _, p in ipairs(pts) do
      if not p.accept and not p.ready then
        local rel = S.Related(m, p.x, p.y, isNear, ctx, DB.ignored, p.q)
        p.related = rel
        for _, q in ipairs(rel.elsewhere) do
          if not fetchSeen[q] then
            fetchSeen[q] = true
            local mapName, _, who = S.StarterInfo(q, m)
            local group = preFetch[mapName]
            if not group then group = {}; preFetch[mapName] = group end
            group[#group + 1] = { q = q, who = who, forQ = p.q }
          end
        end
      end
    end
  end
  return pts, others
end

local function clusterPoints(m, pts)
  local clusters = {}
  for _, p in ipairs(pts) do
    local home
    for _, c in ipairs(clusters) do
      if dist(m, c.x, c.y, p.x, p.y) <= CLUSTER_RADIUS then home = c break end
    end
    if home then
      home.items[#home.items + 1] = p
    else
      clusters[#clusters + 1] = { x = p.x, y = p.y, items = { p } }
    end
  end
  return clusters
end

-- Nächster Nachbar ab Spielerposition, danach 2-opt für einen offenen Pfad.
-- constraints: { {a, b}, ... } heisst Ort a muss vor Ort b kommen (Indizes in cl).
local function orderClusters(m, px, py, cl, constraints)
  local n = #cl
  if n < 2 then return cl end
  local order, used = {}, {}
  local cx, cy = px, py
  for _ = 1, n do
    local best, bd
    for i, c in ipairs(cl) do
      if not used[i] then
        local d = dist(m, cx, cy, c.x, c.y)
        if not bd or d < bd then best, bd = i, d end
      end
    end
    used[best] = true
    order[#order + 1] = best
    cx, cy = cl[best].x, cl[best].y
  end

  -- Bewertung: Weglaenge plus Strafzuschlag, wenn Annehmen-Orte spaet kommen.
  -- Frueh annehmen heisst, die Ziele dieser Quests unterwegs miterledigen zu koennen.
  local hasAccept = {}
  for i, c in ipairs(cl) do
    for _, it in ipairs(c.items) do if it.accept then hasAccept[i] = true break end end
  end
  local pos = {}
  local function cost(o)
    local total, x, y = 0, px, py
    local penalty = 0
    for rank, idx in ipairs(o) do
      local c = cl[idx]
      total = total + dist(m, x, y, c.x, c.y)
      if hasAccept[idx] then penalty = penalty + total end
      x, y = c.x, c.y
      pos[idx] = rank
    end
    local violations = 0
    for _, k in ipairs(constraints or {}) do
      if pos[k[1]] > pos[k[2]] then violations = violations + 1 end
    end
    return total + ACCEPT_WEIGHT * penalty + violations * 1e7
  end

  local best = cost(order)
  local improved, guard = true, 0
  while improved and guard < 30 do
    improved, guard = false, guard + 1
    -- 2-opt: Teilstueck umdrehen
    for i = 1, n - 1 do
      for k = i + 1, n do
        local a, b = i, k
        while a < b do order[a], order[b] = order[b], order[a]; a, b = a + 1, b - 1 end
        local c = cost(order)
        if c < best - 0.5 then
          best, improved = c, true
        else
          a, b = i, k
          while a < b do order[a], order[b] = order[b], order[a]; a, b = a + 1, b - 1 end
        end
      end
    end
    -- Verschieben: einzelnen Ort an eine andere Stelle setzen
    for i = 1, n do
      for j = 1, n do
        if i ~= j then
          local v = table.remove(order, i)
          table.insert(order, j, v)
          local c = cost(order)
          if c < best - 0.5 then
            best, improved = c, true
          else
            table.remove(order, j)
            table.insert(order, i, v)
          end
        end
      end
    end
  end

  local res = {}
  for i, idx in ipairs(order) do res[i] = cl[idx] end
  return res
end

-- Gesamte Route: festgenagelter Ort zuerst, dann optimiert, geparkte Quests am Schluss
local pinnedQuest              -- Quest-ID des festgenagelten Orts (nur für diese Sitzung)

local function buildRoute(m, px, py, pts)
  local normal, parked = {}, {}
  for _, p in ipairs(pts) do
    if DB.parked[p.q] then p.parked = true; parked[#parked + 1] = p
    else normal[#normal + 1] = p end
  end
  local clusters = clusterPoints(m, normal)

  local pinned
  if pinnedQuest then
    for i, c in ipairs(clusters) do
      for _, it in ipairs(c.items) do
        if it.q == pinnedQuest then pinned = table.remove(clusters, i) break end
      end
      if pinned then break end
    end
    if not pinned then pinnedQuest = nil end   -- erledigt oder nicht mehr in der Zone
  end

  -- Bedingungen: Quest, deren Ziele bei Ort b liegen, zuerst annehmen (Ort a vor b)
  local where = {}
  for ci, c in ipairs(clusters) do
    for _, it in ipairs(c.items) do where[it.q] = ci end
  end
  local constraints = {}
  for ci, c in ipairs(clusters) do
    c.alsoHere = nil
    for _, it in ipairs(c.items) do
      for _, q in ipairs(it.related and it.related.now or {}) do
        local a = where[q]
        if a then
          if a ~= ci then constraints[#constraints + 1] = { a, ci } end
          c.alsoHere = c.alsoHere or {}
          c.alsoHere[#c.alsoHere + 1] = q
        end
      end
    end
  end

  local res = {}
  local sx, sy = px, py
  if pinned then
    pinned.pinned = true
    res[1] = pinned
    sx, sy = pinned.x, pinned.y
  end
  for _, c in ipairs(orderClusters(m, sx, sy, clusters, constraints)) do
    res[#res + 1] = c
    sx, sy = c.x, c.y
  end
  for _, c in ipairs(orderClusters(m, sx, sy, clusterPoints(m, parked))) do
    c.parked = true
    res[#res + 1] = c
  end
  return res
end

------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------
local panel = CreateFrame("Frame", "WegweiserPanel", UIParent)
panel:SetSize(280, 60)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetClampedToScreen(true)
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint()
  DB.pos = { p, rp, x, y }
end)

local bg = panel:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.55)

local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
header:SetPoint("TOPLEFT", 8, -6)
header:SetPoint("RIGHT", -64, 0)
header:SetJustifyH("LEFT")
header:SetText("Wegweiser")

local refresh = CreateFrame("Button", nil, panel)
refresh:SetSize(16, 16)
refresh:SetPoint("TOPRIGHT", -22, -3)
refresh:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
refresh:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
-- Kurzes Aufleuchten des Panels als Rückmeldung
local flash = panel:CreateTexture(nil, "BORDER")
flash:SetAllPoints()
flash:SetColorTexture(1, 0.82, 0, 1)
flash:SetAlpha(0)
local flashUntil = 0
local function flashPanel()
  local start = GetTime()
  flashUntil = start + 2.5
  local function step()
    local t = GetTime() - start
    if t >= 0.4 then flash:SetAlpha(0) return end
    flash:SetAlpha(0.25 * (1 - t / 0.4))
    C_Timer.After(0.03, step)
  end
  step()
  C_Timer.After(2.6, function() if ns.renderHeader then ns.renderHeader() end end)
end
ns.IsFlashing = function() return GetTime() < flashUntil end

refresh:SetScript("OnClick", function(self)
  if ns.forceRecalc then ns.forceRecalc() end
  self:Disable()
  C_Timer.After(0.6, function() self:Enable() end)
  flashPanel()
  if ns.renderHeader then ns.renderHeader() end
end)
refresh:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine(L["Route neu berechnen"])
  GameTooltip:Show()
end)
refresh:SetScript("OnLeave", function() GameTooltip:Hide() end)

local gear = CreateFrame("Button", nil, panel)
gear:SetSize(16, 16)
gear:SetPoint("RIGHT", refresh, "LEFT", -3, 0)
gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
gear:SetScript("OnClick", function() if ns.ToggleOptions then ns.ToggleOptions() end end)
gear:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine(L["Einstellungen und Bedienung"])
  GameTooltip:Show()
end)
gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetSize(20, 20)
close:SetPoint("TOPRIGHT", 0, 0)
close:SetScript("OnClick", function() panel:Hide(); DB.shown = false end)

local footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
footer:SetJustifyH("LEFT")

local rows = {}
local ROW_H = 16

local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Button", nil, panel)
  r:SetHeight(ROW_H)
  r:SetPoint("TOPLEFT", 8, -24 - (i - 1) * ROW_H)
  r:SetPoint("RIGHT", -8, 0)
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.text:SetPoint("LEFT")
  r.text:SetPoint("RIGHT", -52, 0)
  r.text:SetJustifyH("LEFT")
  r.text:SetWordWrap(false)
  r.dist = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.dist:SetPoint("RIGHT")
  r.dist:SetJustifyH("RIGHT")
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, button)
    if not self.stop then return end
    if button == "LeftButton" and IsShiftKeyDown() then
      ns.TogglePin(self.stop)
    elseif button == "LeftButton" and IsControlKeyDown() then
      ns.TogglePark(self.stop)
    elseif button == "RightButton" then
      local hidden = 0
      for _, it in ipairs(self.stop.items) do
        if it.accept then DB.ignored[it.q] = true; hidden = hidden + 1 end
      end
      if hidden > 0 then
        msg(hidden .. L[" Vorschlag/Vorschläge ausgeblendet. Zurücksetzen mit /ww unignore"])
        ns.recalc()
      end
    else
      trackStop(self.stop, routeMapID)
    end
  end)
  r:SetScript("OnEnter", function(self)
    if not self.stop then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(string.format(L["Ort %d"], self.index))
    local hasAccept = false
    for _, it in ipairs(self.stop.items) do
      local t = title(it.q)
      if it.ready then
        GameTooltip:AddLine((it.guess and L["Abgeben (beim Questgeber?): "] or L["Abgeben: "]) .. t, 0.25, 1, 0.25)
      elseif it.accept then
        hasAccept = true
        local lvl = ns.Suggest.Level(it.q)
        GameTooltip:AddDoubleLine(L["Annehmen: "] .. t, lvl > 0 and (L["Stufe "] .. lvl) or "", 0.4, 0.73, 1, 0.7, 0.7, 0.7)
      else
        GameTooltip:AddDoubleLine(t, progress(it.q), 1, 1, 1, 0.7, 0.7, 0.7)
      end
    end
    if self.stop.alsoHere then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L["Hier gleich mit erledigen:"], 0.4, 0.73, 1)
      for _, q in ipairs(self.stop.alsoHere) do
        GameTooltip:AddLine("  " .. title(q) .. L[" (wird vorher angenommen)"], 1, 1, 1)
      end
    end
    local later = ns.LaterOf(self.stop)
    if #later > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L["Kommt später nochmal hierher:"], 1, 0.6, 0)
      for _, l in ipairs(later) do
        GameTooltip:AddDoubleLine("  " .. title(l.q), l.why, 1, 1, 1, 0.7, 0.7, 0.7)
      end
      if not self.stop.parked then
        GameTooltip:AddLine(L["Tipp: Strg-Klick parkt diesen Ort, bis du alles zusammen erledigen kannst."],
          1, 0.82, 0, true)
      end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Klick: diesen Ort verfolgen"], 0.6, 0.6, 0.6)
    GameTooltip:AddLine(self.stop.pinned and L["Shift-Klick: Festnageln aufheben"]
      or L["Shift-Klick: als Nächstes festnageln"], 0.6, 0.6, 0.6)
    GameTooltip:AddLine(self.stop.parked and L["Strg-Klick: wieder einplanen"]
      or L["Strg-Klick: auf später parken"], 0.6, 0.6, 0.6)
    if hasAccept then GameTooltip:AddLine(L["Rechtsklick: Vorschlag ausblenden"], 0.6, 0.6, 0.6) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

-- Zeilen für «Vorher holen in ...»
fetchRows = {}
function getFetchRow(i)
  if fetchRows[i] then return fetchRows[i] end
  local f = CreateFrame("Button", nil, panel)
  f:SetHeight(ROW_H)
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.text:SetPoint("LEFT")
  f.text:SetPoint("RIGHT")
  f.text:SetJustifyH("LEFT")
  f.text:SetWordWrap(false)
  local hl = f:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  f:RegisterForClicks("RightButtonUp")
  f:SetScript("OnClick", function(self)
    if not self.group then return end
    for _, e in ipairs(self.group.list) do DB.ignored[e.q] = true end
    msg(L["Ausgeblendet. Zurücksetzen mit /ww unignore oder in den Einstellungen."])
    ns.recalc()
  end)
  f:SetScript("OnEnter", function(self)
    if not self.group then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(L["Vorher holen in"] .. " " .. self.group.name, 1, 0.6, 0)
    GameTooltip:AddLine(L["Diese Quests haben ihre Ziele an Orten deiner Route."], 0.8, 0.8, 0.8, true)
    for _, e in ipairs(self.group.list) do
      GameTooltip:AddLine(" ")
      GameTooltip:AddDoubleLine(title(e.q), e.who or "", 1, 1, 1, 0.4, 0.73, 1)
      GameTooltip:AddLine(L["  gleiches Gebiet wie: "] .. title(e.forQ), 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Rechtsklick: ausblenden"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  fetchRows[i] = f
  return f
end

-- Quests, die später nochmal an diesen Ort führen (ohne Doppelte)
function ns.LaterOf(stop)
  local res, seen = {}, {}
  for _, it in ipairs(stop.items) do
    for _, l in ipairs(it.related and it.related.later or {}) do
      if not seen[l.q] then seen[l.q] = true; res[#res + 1] = l end
    end
  end
  return res
end

local function stopLabel(stop)
  local parts = {}
  for _, it in ipairs(stop.items) do
    if it.ready then
      parts[#parts + 1] = COLOR_DONE .. L["Abgeben:"] .. "|r " .. title(it.q)
    elseif it.accept then
      parts[#parts + 1] = COLOR_ACCEPT .. L["Annehmen:"] .. "|r " .. title(it.q)
    else
      local p = progress(it.q)
      parts[#parts + 1] = title(it.q) .. (p ~= "" and (" " .. COLOR_DIM .. p .. "|r") or "")
    end
  end
  return table.concat(parts, " + ")
end

local function updateDistances()
  if not routeMapID then return end
  local m, px, py = playerPos()
  for i, stop in ipairs(route) do
    local r = rows[i]
    if r and r:IsShown() then
      if m == routeMapID and px then
        local d = dist(m, px, py, stop.x, stop.y) * YARD_TO_M
        r.dist:SetText(d >= 1000 and string.format("%.1f km", d / 1000) or string.format("%d m", math.floor(d / 10 + 0.5) * 10))
      else
        r.dist:SetText("")
      end
    end
  end
end

-- Kopfzeile: Kartenname, nach «neu berechnen» kurz die Bestätigung
function ns.renderHeader()
  if ns.IsFlashing and ns.IsFlashing() then
    local n = #route
    header:SetText("Wegweiser" .. COLOR_DONE .. "  " .. L["neu berechnet"] .. "|r |TInterface\\RaidFrame\\ReadyCheck-Ready:12|t" ..
      COLOR_DIM .. "  " .. n .. " " .. (n == 1 and L["Ort"] or L["Orte"]) .. "|r")
    return
  end
  local mapName = routeMapID and (safe(C_Map.GetMapInfo, routeMapID) or {}).name
  header:SetText("Wegweiser" .. (mapName and (COLOR_DIM .. "  " .. mapName .. "|r") or ""))
end

local function renderPanel()
  ns.renderHeader()

  -- Abschnitt «Vorher holen in ...» (Questgeber in anderen Zonen)
  local groups = {}
  for mapName, list in pairs(preFetch) do groups[#groups + 1] = { name = mapName, list = list } end
  table.sort(groups, function(a, b) return #a.list > #b.list end)
  local top = 0
  for gi, g in ipairs(groups) do
    if gi > 3 then break end
    local f = getFetchRow(gi)
    f.group = g
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", 8, -24 - top)
    f:SetPoint("RIGHT", -8, 0)
    f.text:SetText(string.format("%s%s %s:|r %d %s", COLOR_LATER, L["Vorher holen in"], g.name, #g.list,
      #g.list == 1 and L["Quest"] or L["Quests"]))
    f:Show()
    top = top + ROW_H
  end
  for gi = math.min(#groups, 3) + 1, #fetchRows do fetchRows[gi]:Hide() end
  if top > 0 then top = top + 4 end

  local n = math.min(#route, MAX_ROWS)
  for i = 1, n do
    local stop = route[i]
    local r = getRow(i)
    r.index, r.stop = i, stop
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 8, -24 - top - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", -8, 0)
    local num = (i == 1 and COLOR_NEXT or "") .. i .. ".|r "
    if stop.pinned then num = num .. COLOR_NEXT .. L["[fix]"] .. "|r " end
    if #ns.LaterOf(stop) > 0 and not stop.parked then num = num .. COLOR_LATER .. "!|r " end
    local extra = stop.alsoHere and (" " .. COLOR_ACCEPT .. "+" .. #stop.alsoHere .. "|r") or ""
    if stop.parked then
      local plain = stopLabel(stop):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      r.text:SetText(COLOR_DIM .. i .. ". " .. L["[später]"] .. " " .. plain .. "|r")
    else
      r.text:SetText(num .. (i == 1 and COLOR_NEXT or "") .. stopLabel(stop) .. "|r" .. extra)
    end
    r:Show()
  end
  for i = n + 1, #rows do rows[i]:Hide() end

  local notes = {}
  if #route == 0 then notes[#notes + 1] = L["Keine Quests in dieser Zone."] end
  if #route > MAX_ROWS then notes[#notes + 1] = "+" .. (#route - MAX_ROWS) .. L[" weitere Orte"] end
  if otherZoneCount > 0 then notes[#notes + 1] = otherZoneCount .. L[" Quest(s) in anderen Zonen"] end
  local S = ns.Suggest
  if DB.suggest and S then
    if S.state == "missing" then notes[#notes + 1] = L["Vorschläge: QuestieDB nicht installiert"]
    elseif S.state == "outdated" then notes[#notes + 1] = L["Vorschläge: QuestieDB zu alt"]
    elseif S.state == "indexing" then notes[#notes + 1] = L["Vorschläge werden geladen ..."]
    elseif S.state == "error" then notes[#notes + 1] = L["Vorschläge: Fehler beim Laden"] end
  end
  local footerText = #notes > 0 and table.concat(notes, " · ") or nil
  footer:ClearAllPoints()
  footer:SetPoint("TOPLEFT", 8, -24 - top - n * ROW_H - 2)
  footer:SetPoint("RIGHT", -8, 0)
  footer:SetWordWrap(true)
  footer:SetText(footerText or "")
  panel:SetHeight(30 + top + n * ROW_H + (footerText and (footer:GetStringHeight() + 4) or 0))
  updateDistances()
end

------------------------------------------------------------------------
-- Weltkarte: Nummern-Pins
------------------------------------------------------------------------
local pins = {}
local canvas
local PIN_SIZE = 20            -- Bildschirmpixel, unabhaengig vom Zoom
local PIN_OFFSET = 11          -- Abzeichen schraeg oben rechts neben dem Blizzard-Symbol
local PIN_LEVEL = 9000         -- ueber den Blizzard-Kartenpins
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local function getPin(i)
  if pins[i] then return pins[i] end
  local p = CreateFrame("Frame", nil, canvas)
  p:SetSize(PIN_SIZE, PIN_SIZE)
  p.ring = p:CreateTexture(nil, "BACKGROUND")
  p.ring:SetPoint("CENTER")
  p.ring:SetSize(PIN_SIZE + 4, PIN_SIZE + 4)
  p.ring:SetTexture(CIRCLE)
  p.ring:SetVertexColor(1, 0.82, 0, 1)
  p.circle = p:CreateTexture(nil, "ARTWORK")
  p.circle:SetAllPoints()
  p.circle:SetTexture(CIRCLE)
  p.label = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  p.label:SetPoint("CENTER", 0, 0)
  p:EnableMouse(true)
  p:SetScript("OnEnter", function(self)
    if not self.stop then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Wegweiser: Ort "] .. self.index)
    for _, it in ipairs(self.stop.items) do
      local prefix = it.ready and L["Abgeben: "] or (it.accept and L["Annehmen: "] or "")
      GameTooltip:AddLine(prefix .. title(it.q), 1, 1, 1)
    end
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  pins[i] = p
  return p
end

-- Pins mit Gegen-Skalierung positionieren: gleich gross bei jedem Zoom.
-- SetPoint-Offsets gelten in der Skala des Pins, deshalb durch k teilen.
local lastScale
local function layoutPins()
  if not canvas then return end
  local cs = canvas:GetEffectiveScale()
  if not cs or cs == 0 then return end
  lastScale = cs
  local k = UIParent:GetEffectiveScale() / cs
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  for _, p in ipairs(pins) do
    if p:IsShown() and p.stop then
      p:SetScale(k)
      p:ClearAllPoints()
      p:SetPoint("CENTER", canvas, "TOPLEFT",
        p.stop.x * w / k + PIN_OFFSET, -p.stop.y * h / k + PIN_OFFSET)
      p:SetFrameLevel(PIN_LEVEL - p.index)   -- Ort 1 liegt zuoberst
    end
  end
end

local function refreshPins()
  if not canvas then return end
  for _, p in ipairs(pins) do p:Hide() end
  if not DB.pins or not WorldMapFrame:IsShown() then return end
  local shown = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
  if not shown or shown ~= routeMapID then return end
  for i, stop in ipairs(route) do
    local p = getPin(i)
    p.index, p.stop = i, stop
    if i == 1 then
      p.circle:SetVertexColor(1, 0.82, 0, 1)
      p.label:SetTextColor(0, 0, 0)
    else
      p.circle:SetVertexColor(0.08, 0.08, 0.08, 0.95)
      p.label:SetTextColor(1, 0.82, 0)
    end
    local acceptOnly = true
    for _, it in ipairs(stop.items) do if not it.accept then acceptOnly = false break end end
    if acceptOnly then p.ring:SetVertexColor(0.4, 0.73, 1, 1) else p.ring:SetVertexColor(1, 0.82, 0, 1) end
    p.label:SetText(i)
    p:Show()
  end
  layoutPins()
end

local function initMap()
  if canvas or not WorldMapFrame then return end
  canvas = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
  if not canvas then return end
  WorldMapFrame:HookScript("OnShow", refreshPins)
  if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", refreshPins) end
  -- Zoom beobachten, solange die Karte offen ist (OnUpdate laeuft nur bei sichtbarer Karte)
  local driver = CreateFrame("Frame", nil, WorldMapFrame)
  driver:SetScript("OnUpdate", function()
    local cs = canvas:GetEffectiveScale()
    if cs ~= lastScale then layoutPins() end
  end)
end

------------------------------------------------------------------------
-- Neuberechnung
------------------------------------------------------------------------
local function recalc()
  local m, px, py = playerPos()
  if not m then return end
  routeMapID = m
  local pts, others = collectPoints(m)
  otherZoneCount = others
  route = buildRoute(m, px or 0.5, py or 0.5, pts)

  local first = route[1]
  if DB.track and first then
    local key
    for _, it in ipairs(first.items) do
      if not it.accept then key = it.q break end
    end
    key = key or string.format("%.3f:%.3f", first.x, first.y)
    if key ~= lastTracked then
      lastTracked = key
      trackStop(first, m)
    end
  end

  if panel:IsShown() then renderPanel() end
  refreshPins()
end
ns.recalc = recalc

-- Vorschlags-Index im Hintergrund aufbauen, danach Route neu rechnen
local indexer = CreateFrame("Frame")
indexer:Hide()
indexer:SetScript("OnUpdate", function(self)
  local S = ns.Suggest
  if not S or S.state ~= "indexing" then self:Hide() return end
  if S.Step() then
    self:Hide()
    recalc()
  end
end)

local pending
local function requestRecalc()
  if pending then return end
  pending = true
  C_Timer.After(0.3, function() pending = false; recalc() end)
end

-- Nach dem Annehmen liefert der Client den Kartenpunkt einer neuen Quest oft erst
-- verzoegert (zuerst steht er beim Questgeber). Deshalb später nochmals rechnen.
local latePending
local function requestLateRecalc()
  if latePending then return end
  latePending = true
  C_Timer.After(2, recalc)
  C_Timer.After(5, function() latePending = false; recalc() end)
end

-- Festnageln: dieser Ort kommt fix auf Platz 1 (bis erledigt oder erneut geklickt)
function ns.TogglePin(stop)
  local q = stop.items[1].q
  if stop.pinned then
    pinnedQuest = nil
    msg(L["Festnageln aufgehoben."])
  else
    pinnedQuest = q
    if stop.parked then for _, it in ipairs(stop.items) do DB.parked[it.q] = nil end end
    msg(L["Als Nächstes festgenagelt: "] .. title(q))
  end
  lastTracked = nil
  recalc()
end

-- Parken: Quests dieses Orts ans Ende schieben (bleibt gespeichert)
function ns.TogglePark(stop)
  local park = not stop.parked
  for _, it in ipairs(stop.items) do
    DB.parked[it.q] = park or nil
    if park and it.q == pinnedQuest then pinnedQuest = nil end
  end
  msg(park and L["Auf später geparkt."] or L["Wieder eingeplant."])
  lastTracked = nil
  recalc()
end

-- Manuell neu berechnen (Knopf im Panel und /ww neu)
local function forceRecalc()
  lastTracked = nil
  sizeCache = {}
  recalc()
end
ns.forceRecalc = forceRecalc

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("QUEST_ACCEPTED")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("QUEST_REMOVED")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("ZONE_CHANGED")
ev:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "ADDON_LOADED" then
    if a1 == ADDON_NAME then
      WegweiserDB = type(WegweiserDB) == "table" and WegweiserDB or {}
      DB = WegweiserDB
      DB.pickups = DB.pickups or {}
      DB.turnins = DB.turnins or {}
      if DB.track == nil then DB.track = true end
      if DB.pins == nil then DB.pins = true end
      if DB.shown == nil then DB.shown = true end
      if DB.suggest == nil then DB.suggest = true end
      DB.ignored = DB.ignored or {}
      DB.parked = DB.parked or {}
      DB.unavailable = DB.unavailable or {}
      panel:ClearAllPoints()
      if DB.pos then
        panel:SetPoint(DB.pos[1], UIParent, DB.pos[2], DB.pos[3], DB.pos[4])
      else
        panel:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
      end
      panel:SetShown(DB.shown)
      initMap()
    elseif a1 == "Blizzard_WorldMap" then
      initMap()
    end
    return
  end
  if not DB then return end
  if event == "QUEST_ACCEPTED" then
    remember("pickups", a2 or a1)       -- je nach Client (index, questID) oder (questID)
    requestLateRecalc()
  elseif event == "QUEST_TURNED_IN" then
    remember("turnins", a1)
    DB.parked[a1] = nil
    if a1 == lastTracked then lastTracked = nil end
    ns.UnlockAfter(a1)
    requestLateRecalc()
  elseif event == "QUEST_REMOVED" then
    if a1 and not safe(C_QuestLog.IsQuestFlaggedCompleted, a1) then DB.parked[a1] = nil end
    requestLateRecalc()
  elseif event == "PLAYER_LEVEL_UP" then
    wipe(DB.unavailable)             -- neue Stufe: alles nochmals prüfen
  elseif event == "GOSSIP_SHOW" or event == "QUEST_GREETING" or event == "QUEST_DETAIL" then
    ns.LearnFromNpc(event)
    return
  elseif event == "PLAYER_ENTERING_WORLD" then
    initMap()
    local S = ns.Suggest
    if DB.suggest and S and S.state == "off" then
      S.Init()
      if S.state == "indexing" then indexer:Show() end
    end
  end
  requestRecalc()
end)
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("GOSSIP_SHOW")
ev:RegisterEvent("QUEST_GREETING")
ev:RegisterEvent("QUEST_DETAIL")

------------------------------------------------------------------------
-- Lernen am Questgeber: Was bietet der NPC wirklich an?
-- Die Datenbank kann Lücken haben (z.B. fehlende Vorquests bei neuen Forever-Quests).
-- Wenn ein NPC eine vorgeschlagene Quest nicht anbietet, wird sie als «nicht verfügbar»
-- gemerkt, bis sie beim nächsten Besuch angeboten wird, eine Vorquest abgegeben wird
-- oder du eine Stufe aufsteigst.
------------------------------------------------------------------------
local function npcIdOf(unit)
  local guid = UnitGUID and UnitGUID(unit)
  if not guid then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind ~= "Creature" then return nil end
  return tonumber(id)
end

local function offeredQuests(event)
  local offered, complete = {}, false
  if event == "GOSSIP_SHOW" and C_GossipInfo and C_GossipInfo.GetAvailableQuests then
    local list = safe(C_GossipInfo.GetAvailableQuests)
    if type(list) == "table" then
      complete = true
      for _, info in ipairs(list) do
        if info.questID then offered[info.questID] = true else complete = false end
      end
    end
  elseif event == "QUEST_GREETING" and GetNumAvailableQuests and GetAvailableQuestInfo then
    complete = true
    for i = 1, GetNumAvailableQuests() or 0 do
      local id = select(5, safe(GetAvailableQuestInfo, i))
      if id then offered[id] = true else complete = false end
    end
  elseif event == "QUEST_DETAIL" and GetQuestID then
    -- Questfenster: zeigt nur eine Quest. Taugt zum Freischalten, nicht zum Sperren,
    -- weil es auch nach einem Klick in einer längeren Liste erscheint.
    local id = safe(GetQuestID)
    if id and id ~= 0 then offered[id] = true end
  end
  return offered, complete
end

function ns.LearnFromNpc(event)
  local S = ns.Suggest
  if not (DB and S and S.state == "ready") then return end
  local npc = npcIdOf("npc")
  local quests = npc and S.QuestsOfNpc(npc)
  if not quests then return end
  local offered, complete = offeredQuests(event)
  local changed = false
  for q in pairs(quests) do
    if offered[q] then
      if DB.unavailable[q] then DB.unavailable[q] = nil; changed = true end
    elseif complete and not inLog(q) and not safe(C_QuestLog.IsQuestFlaggedCompleted, q)
      and not DB.unavailable[q] then
      DB.unavailable[q] = true
      changed = true
    end
  end
  if changed then lastTracked = nil; requestRecalc() end
end

-- Nach einer Abgabe: Sperren von Quests aufheben, deren Vorquest das war
function ns.UnlockAfter(turnedIn)
  local S = ns.Suggest
  if not (DB and S and S.state == "ready" and turnedIn) then return end
  for q in pairs(DB.unavailable) do
    local pg, ps = S.Prereqs(q)
    for _, list in ipairs({ pg or {}, ps or {} }) do
      for _, p in ipairs(list) do
        if p == turnedIn then DB.unavailable[q] = nil end
      end
    end
  end
end

-- Distanzen laufend aktualisieren, Route alle 10 Sekunden neu rechnen
local tick = 0
C_Timer.NewTicker(1, function()
  if not DB then return end
  tick = tick + 1
  if tick % 10 == 0 then recalc() elseif panel:IsShown() then updateDistances() end
end)

------------------------------------------------------------------------
-- Einstellungen (gemeinsam für Slash-Befehle und Einstellungsfenster)
------------------------------------------------------------------------
local function startSuggest()
  local S = ns.Suggest
  if DB.suggest and S and S.state == "off" then
    S.Init()
    if S.state == "indexing" then indexer:Show() end
  end
end

local function resetPosition()
  DB.pos = nil
  panel:ClearAllPoints()
  panel:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
  panel:Show(); DB.shown = true
end

-- Ein Schalter aendern; value = nil heisst umschalten
function ns.Set(key, value)
  if value == nil then value = not DB[key] end
  if key == "shown" then
    DB.shown = value
    panel:SetShown(value)
    if value then recalc() end
  elseif key == "track" then
    DB.track = value
    lastTracked = nil
    if not value then safe(C_Map.ClearUserWaypoint) end
    recalc()
  elseif key == "pins" then
    DB.pins = value
    refreshPins()
  elseif key == "suggest" then
    DB.suggest = value
    startSuggest()
    recalc()
  elseif key == "grey" then
    DB.grey = value
    recalc()
  end
  if ns.RefreshOptions then ns.RefreshOptions() end
  return value
end

function ns.Get(key) return DB and DB[key] end

function ns.CountOf(key)
  local n = 0
  for _ in pairs(DB and DB[key] or {}) do n = n + 1 end
  return n
end

function ns.ResetList(key)
  wipe(DB[key])
  if key == "parked" then pinnedQuest = nil end
  lastTracked = nil
  recalc()
  if ns.RefreshOptions then ns.RefreshOptions() end
end

ns.ResetPosition = resetPosition

------------------------------------------------------------------------
-- Slash-Befehle
------------------------------------------------------------------------
local LABELS = {
  track = L["Nächsten Ort automatisch verfolgen"], pins = L["Nummern auf der Weltkarte"],
  suggest = L["Vorschläge zum Annehmen"], grey = L["Graue Quests vorschlagen"],
}

SLASH_WEGWEISER1 = "/ww"
SLASH_WEGWEISER2 = "/wegweiser"
SlashCmdList.WEGWEISER = function(input)
  local cmd = (input or ""):lower():match("^%s*(%S*)")
  if cmd == "grau" then cmd = "grey" end
  if LABELS[cmd] then
    local v = ns.Set(cmd)
    msg(LABELS[cmd] .. ": " .. (v and L["an"] or L["aus"]))
  elseif cmd == "optionen" or cmd == "options" or cmd == "o" or cmd == "hilfe" or cmd == "help" then
    if ns.ToggleOptions then ns.ToggleOptions() end
  elseif cmd == "neu" or cmd == "refresh" or cmd == "r" then
    forceRecalc()
    msg(L["Route neu berechnet."])
  elseif cmd == "unignore" then
    ns.ResetList("ignored")
    msg(L["Alle ausgeblendeten Vorschläge werden wieder angezeigt."])
  elseif cmd == "unpark" then
    ns.ResetList("parked")
    msg(L["Alle geparkten Quests sind wieder eingeplant."])
  elseif cmd == "reset" then
    resetPosition()
  else
    ns.Set("shown", not panel:IsShown())
  end
end
