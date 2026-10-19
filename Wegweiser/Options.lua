-- Wegweiser: Einstellungsfenster mit allen Schaltern und einer Bedienungsübersicht.
-- Oeffnen: Zahnrad im Panel oder /ww optionen. Zusaetzlich unter Esc > Optionen > AddOns.

local _, ns = ...
local L = ns.L

local W, PAD = 360, 16
local win
local checks, buttons = {}, {}

local OPTIONS = {
  { key = "shown",   label = L["Panel anzeigen"] },
  { key = "track",   label = L["Nächsten Ort automatisch verfolgen"],
    hint = L["Setzt die Quest bzw. eine Kartenmarkierung für Ort 1."] },
  { key = "pins",    label = L["Nummern auf der Weltkarte"] },
  { key = "suggest", label = L["Vorschläge zum Annehmen"],
    hint = L["Benötigt das Addon QuestieDB."] },
  { key = "grey",    label = L["Auch graue (zu tiefe) Quests vorschlagen"] },
}

local HELP = {
  { L["Klick"],         L["Ort verfolgen"] },
  { L["Shift-Klick"],   L["als Nächstes festnageln (nochmals: aufheben)"] },
  { L["Strg-Klick"],    L["auf später parken (nochmals: wieder einplanen)"] },
  { L["Rechtsklick"],   L["Vorschlag ausblenden"] },
  { L["Pfeil-Knopf"],   L["Route sofort neu berechnen"] },
  { "|cffff9900!|r  " .. L["im Panel"],  L["Ort kommt später nochmal (Grund im Tooltip)"] },
  { "|cff66bbff+1|r " .. L["im Panel"], L["andere Quest hier gleich miterledigen"] },
  { L["Vorher holen"],  L["Quests aus anderen Zonen für deine Route"] },
  { L["Panel ziehen"],  L["verschieben"] },
}

local COMMANDS = L["/ww  Panel ein/aus   ·   /ww optionen   ·   /ww neu"]

local function suggestStatus()
  local S = ns.Suggest
  if not ns.Get("suggest") then return "" end
  if not S then return "" end
  local map = {
    missing = "|cffff6060" .. L["QuestieDB nicht installiert"] .. "|r",
    outdated = "|cffff6060" .. L["QuestieDB zu alt"] .. "|r",
    indexing = "|cffffd100" .. L["wird geladen ..."] .. "|r",
    ready = "|cff40ff40" .. L["bereit"] .. "|r",
    error = "|cffff6060" .. L["Fehler beim Laden"] .. "|r",
  }
  return map[S.state] or ""
end

function ns.RefreshOptions()
  if not win or not win:IsShown() then return end
  for _, c in ipairs(checks) do c:SetChecked(ns.Get(c.key) and true or false) end
  checks.suggestStatus:SetText(suggestStatus())
  buttons.ignored:SetText(string.format(L["Ausgeblendete Vorschläge zeigen (%d)"], ns.CountOf("ignored")))
  buttons.parked:SetText(string.format(L["Geparkte Quests einplanen (%d)"], ns.CountOf("parked")))
  buttons.unavailable:SetText(string.format(L["Am Questgeber gelernte Sperren löschen (%d)"], ns.CountOf("unavailable")))
end

local function build()
  local ok, f = pcall(CreateFrame, "Frame", "WegweiserOptions", UIParent, "BasicFrameTemplateWithInset")
  if not ok or not f then
    f = CreateFrame("Frame", "WegweiserOptions", UIParent)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.92)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT")
  end
  f:SetSize(W, 470)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetScript("OnShow", ns.RefreshOptions)
  tinsert(UISpecialFrames, "WegweiserOptions")      -- mit Esc schliessen

  local hasTitle = type(f.TitleText) == "table"
  local title = hasTitle and f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if not hasTitle then title:SetPoint("TOP", 0, -8) end
  title:SetText(L["Wegweiser - Einstellungen"])

  local y = -34
  local function heading(text)
    local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", PAD, y)
    h:SetText(text)
    y = y - 22
  end

  heading(L["Anzeige"])
  for _, o in ipairs(OPTIONS) do
    local c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c:SetPoint("TOPLEFT", PAD - 4, y + 4)
    c.key = o.key
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    label:SetText(o.label)
    c:SetScript("OnClick", function(self) ns.Set(self.key, self:GetChecked() and true or false) end)
    if o.hint then
      c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(o.label)
        GameTooltip:AddLine(o.hint, 1, 1, 1, true)
        GameTooltip:Show()
      end)
      c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    if o.key == "suggest" then
      checks.suggestStatus = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      checks.suggestStatus:SetPoint("LEFT", label, "RIGHT", 8, 0)
    end
    checks[#checks + 1] = c
    y = y - 24
  end

  y = y - 8
  heading(L["Zurücksetzen"])
  local function button(key, onClick)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(W - 2 * PAD, 22)
    b:SetPoint("TOPLEFT", PAD, y)
    b:SetScript("OnClick", onClick)
    buttons[key] = b
    y = y - 26
    return b
  end
  button("ignored", function() ns.ResetList("ignored") end)
  button("parked", function() ns.ResetList("parked") end)
  button("unavailable", function() ns.ResetList("unavailable") end)
  button("position", function() ns.ResetPosition() end):SetText(L["Panel-Position zurücksetzen"])

  y = y - 8
  heading(L["Bedienung im Panel"])
  for _, h in ipairs(HELP) do
    local k = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    k:SetPoint("TOPLEFT", PAD, y)
    k:SetWidth(100)
    k:SetJustifyH("LEFT")
    k:SetText("|cffffd100" .. h[1] .. "|r")
    local v = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    v:SetPoint("LEFT", k, "RIGHT", 4, 0)
    v:SetText(h[2])
    y = y - 16
  end

  y = y - 6
  local cmd = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  cmd:SetPoint("TOPLEFT", PAD, y)
  cmd:SetText(COMMANDS)
  y = y - 20

  f:SetHeight(-y + 8)
  f:Hide()
  return f
end

function ns.ToggleOptions()
  if not win then win = build() end
  win:SetShown(not win:IsShown())
end

-- Eintrag im Blizzard-Einstellungsmenue (Esc > Optionen > AddOns), falls verfuegbar
local function registerBlizzard()
  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
  local canvas = CreateFrame("Frame")
  local t = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  t:SetPoint("TOPLEFT", 16, -16)
  t:SetText("Wegweiser")
  local b = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
  b:SetSize(220, 24)
  b:SetPoint("TOPLEFT", 16, -48)
  b:SetText(L["Einstellungen öffnen"])
  b:SetScript("OnClick", function()
    if SettingsPanel and SettingsPanel.Hide then pcall(SettingsPanel.Hide, SettingsPanel) end
    if not win then win = build() end
    win:Show()
  end)
  local category = Settings.RegisterCanvasLayoutCategory(canvas, "Wegweiser")
  Settings.RegisterAddOnCategory(category)
end
pcall(registerBlizzard)
