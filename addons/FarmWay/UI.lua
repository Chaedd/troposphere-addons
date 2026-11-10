-- Panneau FarmWay sur la carte du monde : liste des routes, création, partage.
local _, ns = ...
local FW, L = ns.FW, ns.L

local UI = {}
ns.UI = UI

local PANEL_W, PANEL_H = 290, 400
local LIST_W, LIST_H = 248, 150
local ROW_H = 22
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local panel, listView, newView, shareFrame

------------------------------------------------------------------------
-- Petits constructeurs
------------------------------------------------------------------------

local function Button(parent, text, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 120, 22)
  b:SetText(text)
  return b
end

local function Check(parent, label)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
  c.label:SetJustifyH("LEFT")
  c.label:SetText(label or "")
  return c
end

local function Text(parent, template, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local function Panel(name, parent, w, h)
  local f = CreateFrame("Frame", name, parent, BACKDROP_TEMPLATE)
  f:SetSize(w, h)
  if f.SetBackdrop then
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.94)
  end
  f:EnableMouse(true)
  return f
end

local function ScrollList(parent, w, h)
  local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  sf:SetSize(w, h)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(w, 1)
  sf:SetScrollChild(child)
  sf.child = child
  return sf
end

local function displayedMap()
  return WorldMapFrame and WorldMapFrame:GetMapID()
end

------------------------------------------------------------------------
-- Vue « liste des routes »
------------------------------------------------------------------------

local routeRows = {}

local function routeRow(i)
  local row = routeRows[i]
  if row then return row end
  local child = listView.scroll.child
  row = CreateFrame("Button", nil, child)
  row:SetSize(LIST_W, ROW_H)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.sel = row:CreateTexture(nil, "BACKGROUND")
  row.sel:SetAllPoints()
  row.sel:SetColorTexture(1, 0.82, 0.2, 0.18)

  row.swatch = CreateFrame("Button", nil, row)
  row.swatch:SetSize(14, 14)
  row.swatch:SetPoint("LEFT", 4, 0)
  row.swatch.tex = row.swatch:CreateTexture(nil, "ARTWORK")
  row.swatch.tex:SetAllPoints()
  row.swatch:SetScript("OnClick", function() FW:CycleColor(row.mapID, row.name) end)
  row.swatch:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Click: change color"])
    GameTooltip:Show()
  end)
  row.swatch:SetScript("OnLeave", GameTooltip_Hide)

  row.visible = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  row.visible:SetSize(20, 20)
  row.visible:SetPoint("LEFT", row.swatch, "RIGHT", 4, 0)
  row.visible:SetScript("OnClick", function(self) FW:SetVisible(row.mapID, row.name, self:GetChecked()) end)

  row.count = Text(row, "GameFontDisableSmall", "RIGHT")
  row.count:SetPoint("RIGHT", -4, 0)
  row.label = Text(row, "GameFontHighlight")
  row.label:SetPoint("LEFT", row.visible, "RIGHT", 2, 0)
  row.label:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
  row.label:SetWordWrap(false)

  row:SetScript("OnClick", function() FW:Select(row.mapID, row.name) end)
  routeRows[i] = row
  return row
end

local function refreshList(mapID)
  local names = FW:GetRouteNames(mapID)
  for i, name in ipairs(names) do
    local r = FW:GetRoute(mapID, name)
    local row = routeRow(i)
    row.mapID, row.name = mapID, name
    row.label:SetText(name)
    row.count:SetText(#r.points .. " " .. L["points"])
    row.swatch.tex:SetColorTexture(r.color[1], r.color[2], r.color[3], 1)
    row.visible:SetChecked(r.visible and true or false)
    row.sel:SetShown(FW:IsSelected(mapID, name) and true or false)
    row:Show()
  end
  for i = #names + 1, #routeRows do routeRows[i]:Hide() end
  listView.scroll.child:SetHeight(math.max(1, #names * ROW_H))
  listView.empty:SetShown(#names == 0)

  local selMap, selName, route = FW:GetSelected()
  local hasSel = selMap == mapID and route ~= nil
  if hasSel then
    listView.selTitle:SetText(selName .. "  |cff999999(" .. #route.points .. " " .. L["points"] .. ")|r")
  else
    listView.selTitle:SetText("|cff999999" .. L["Select a route in the list."] .. "|r")
  end
  local editing = (hasSel and FW.editing) and true or false
  for _, b in ipairs(listView.selButtons) do b:SetEnabled(hasSel) end
  listView.refresh:SetEnabled((hasSel and route.sources ~= nil and ns.Sources.Available()) and true or false)
  listView.optimize:SetEnabled((hasSel and #route.points >= 4) and true or false)
  listView.edit:SetEnabled(hasSel)
  listView.edit:SetChecked(editing)
  listView.editHelp:SetShown(editing)
  listView.minimap:SetChecked(FW.db.settings.minimap and true or false)
end

local function buildList()
  listView = CreateFrame("Frame", nil, panel)
  listView:SetPoint("TOPLEFT", 10, -46)
  listView:SetPoint("BOTTOMRIGHT", -10, 10)

  listView.scroll = ScrollList(listView, LIST_W, LIST_H)
  listView.scroll:SetPoint("TOPLEFT", 0, 0)
  listView.empty = Text(listView, "GameFontDisable", "CENTER")
  listView.empty:SetPoint("TOPLEFT", listView.scroll, "TOPLEFT", 4, -40)
  listView.empty:SetPoint("RIGHT", listView.scroll, "RIGHT", -4, 0)
  listView.empty:SetText(L["No route in this zone yet.\nClick \"New route\" to create one."])

  listView.selTitle = Text(listView, "GameFontNormal")
  listView.selTitle:SetPoint("TOPLEFT", listView.scroll, "BOTTOMLEFT", 0, -10)
  listView.selTitle:SetPoint("RIGHT", listView, "RIGHT", 0, 0)
  listView.selTitle:SetWordWrap(false)

  listView.optimize = Button(listView, L["Optimize"], 130)
  listView.optimize:SetPoint("TOPLEFT", listView.selTitle, "BOTTOMLEFT", 0, -6)
  listView.optimize:SetScript("OnClick", function()
    local mapID, name = FW:GetSelected()
    FW:OptimizeRoute(mapID, name)
  end)

  listView.refresh = Button(listView, L["Update"], 130)
  listView.refresh:SetPoint("LEFT", listView.optimize, "RIGHT", 8, 0)
  listView.refresh:SetScript("OnClick", function()
    local mapID, name = FW:GetSelected()
    local count = FW:RefreshFromSources(mapID, name)
    if count then FW:Print(format(L["Route updated from GatherMate2: %d points."], count)) end
  end)

  listView.share = Button(listView, L["Share"], 130)
  listView.share:SetPoint("TOPLEFT", listView.optimize, "BOTTOMLEFT", 0, -4)
  listView.share:SetScript("OnClick", function()
    local mapID, name = FW:GetSelected()
    UI:ShowShare(FW:ExportRoute(mapID, name))
  end)

  listView.delete = Button(listView, L["Delete"], 130)
  listView.delete:SetPoint("LEFT", listView.share, "RIGHT", 8, 0)
  listView.delete:SetScript("OnClick", function()
    local mapID, name = FW:GetSelected()
    if not mapID then return end
    local dialog = StaticPopup_Show("FARMWAY_DELETE", name)
    if dialog then dialog.data = { mapID = mapID, name = name } end
  end)
  listView.selButtons = { listView.share, listView.delete }

  listView.edit = Check(listView, L["Edit on map"])
  listView.edit:SetPoint("TOPLEFT", listView.share, "BOTTOMLEFT", -2, -6)
  listView.edit:SetScript("OnClick", function(self) FW:SetEditing(self:GetChecked()) end)
  listView.editHelp = Text(listView, "GameFontHighlightSmall")
  listView.editHelp:SetPoint("TOPLEFT", listView.edit, "BOTTOMLEFT", 2, -2)
  listView.editHelp:SetPoint("RIGHT", listView, "RIGHT", 0, 0)
  listView.editHelp:SetTextColor(1, 0.82, 0.2)
  listView.editHelp:SetText(L["Edit mode: click the map to add a point, right-click a point to remove it"])

  listView.new = Button(listView, L["New route"], 130)
  listView.new:SetPoint("BOTTOMLEFT", 0, 26)
  listView.new:SetScript("OnClick", function() UI:ShowNew() end)

  listView.import = Button(listView, L["Import"], 130)
  listView.import:SetPoint("LEFT", listView.new, "RIGHT", 8, 0)
  listView.import:SetScript("OnClick", function() UI:ShowShare(nil) end)

  listView.minimap = Check(listView, L["Show on minimap"])
  listView.minimap:SetPoint("BOTTOMLEFT", -2, -2)
  listView.minimap:SetScript("OnClick", function(self)
    FW.db.settings.minimap = self:GetChecked() and true or false
    FW:Fire()
  end)
end

------------------------------------------------------------------------
-- Vue « nouvelle route » : on coche des ressources, un clic et c'est prêt.
------------------------------------------------------------------------

local kindRows = {}

local function kindRow(i)
  local row = kindRows[i]
  if row then return row end
  local child = newView.scroll.child
  row = CreateFrame("Frame", nil, child)
  row:SetSize(LIST_W, ROW_H)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  row.header = Text(row, "GameFontNormal")
  row.header:SetPoint("LEFT", 2, 0)
  row.check = Check(row, "")
  row.check:SetPoint("LEFT", 6, 0)
  kindRows[i] = row
  return row
end

function UI:RefreshNew()
  local mapID = displayedMap()
  local kinds = ns.Sources.ListNodeKinds(mapID)
  local i, lastType = 0, nil
  for _, kind in ipairs(kinds) do
    if kind.db ~= lastType then
      i = i + 1
      local h = kindRow(i)
      h.kind = nil
      h.header:SetText(ns.Sources.TypeLabel(kind.db))
      h.header:Show()
      h.check:Hide()
      h:Show()
      lastType = kind.db
    end
    i = i + 1
    local row = kindRow(i)
    row.kind = kind
    row.header:Hide()
    row.check.label:SetText(format("%s |cff999999(%d)|r", kind.name, kind.count))
    row.check:SetChecked(false)
    row.check:Show()
    row:Show()
  end
  for j = i + 1, #kindRows do kindRows[j]:Hide() end
  newView.scroll.child:SetHeight(math.max(1, i * ROW_H))

  if not ns.Sources.Available() then
    newView.info:SetText(L["Install GatherMate2 to build routes automatically. You can still create an empty route and add points yourself."])
  elseif #kinds == 0 then
    newView.info:SetText(L["GatherMate2 has no resource for this zone yet. Create an empty route and add points yourself."])
  else
    newView.info:SetText("")
  end
  newView.create:SetEnabled(#kinds > 0)
end

local function selectedKinds()
  local out = {}
  for _, row in ipairs(kindRows) do
    if row:IsShown() and row.kind and row.check:GetChecked() then
      out[#out + 1] = { db = row.kind.db, id = row.kind.id }
    end
  end
  return out
end

local function defaultName()
  local mapID = displayedMap()
  return FW:UniqueName(mapID, FW:ZoneName(mapID))
end

local function buildNew()
  newView = CreateFrame("Frame", nil, panel)
  newView:SetPoint("TOPLEFT", 10, -46)
  newView:SetPoint("BOTTOMRIGHT", -10, 10)

  local nameLabel = Text(newView, "GameFontNormalSmall")
  nameLabel:SetPoint("TOPLEFT", 0, 0)
  nameLabel:SetText(L["Route name"])
  newView.name = CreateFrame("EditBox", nil, newView, "InputBoxTemplate")
  newView.name:SetSize(240, 20)
  newView.name:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -2)
  newView.name:SetAutoFocus(false)
  newView.name:SetMaxLetters(40)
  newView.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  newView.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

  local srcLabel = Text(newView, "GameFontNormalSmall")
  srcLabel:SetPoint("TOPLEFT", newView.name, "BOTTOMLEFT", -6, -10)
  srcLabel:SetPoint("RIGHT", newView, "RIGHT", 0, 0)
  srcLabel:SetText(L["Resources found by GatherMate2 in this zone:"])

  newView.scroll = ScrollList(newView, LIST_W, LIST_H + 20)
  newView.scroll:SetPoint("TOPLEFT", srcLabel, "BOTTOMLEFT", 0, -4)
  newView.info = Text(newView, "GameFontDisable")
  newView.info:SetPoint("TOPLEFT", newView.scroll, "TOPLEFT", 4, -20)
  newView.info:SetPoint("RIGHT", newView.scroll, "RIGHT", -4, 0)

  newView.create = Button(newView, L["Create route"], 268)
  newView.create:SetPoint("BOTTOMLEFT", 0, 26)
  newView.create:SetScript("OnClick", function()
    local selections = selectedKinds()
    if #selections == 0 then
      FW:Print(L["Tick at least one resource."])
      return
    end
    local name, route = FW:CreateFromSources(displayedMap(), newView.name:GetText(), selections)
    if name then
      FW:Print(format(L["Route created: %s (%d points)."], name, #route.points))
      UI:ShowList()
    end
  end)

  newView.empty = Button(newView, L["Empty route"], 130)
  newView.empty:SetPoint("BOTTOMLEFT", 0, 0)
  newView.empty:SetScript("OnClick", function()
    FW:CreateRoute(displayedMap(), newView.name:GetText())
    FW:SetEditing(true)
    UI:ShowList()
  end)

  newView.cancel = Button(newView, L["Cancel"], 130)
  newView.cancel:SetPoint("LEFT", newView.empty, "RIGHT", 8, 0)
  newView.cancel:SetScript("OnClick", function() UI:ShowList() end)
end

------------------------------------------------------------------------
-- Fenêtre de partage (export et import)
------------------------------------------------------------------------

local function buildShare()
  shareFrame = Panel("FarmWayShareFrame", UIParent, 420, 220)
  shareFrame:SetPoint("CENTER")
  shareFrame:SetFrameStrata("DIALOG")
  shareFrame:SetMovable(true)
  shareFrame:RegisterForDrag("LeftButton")
  shareFrame:SetScript("OnDragStart", shareFrame.StartMoving)
  shareFrame:SetScript("OnDragStop", shareFrame.StopMovingOrSizing)
  shareFrame:Hide()
  tinsert(UISpecialFrames, "FarmWayShareFrame")

  local title = Text(shareFrame, "GameFontNormal")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("FarmWay")
  shareFrame.help = Text(shareFrame, "GameFontHighlightSmall")
  shareFrame.help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  shareFrame.help:SetPoint("RIGHT", -14, 0)

  local scroll = CreateFrame("ScrollFrame", nil, shareFrame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -52)
  scroll:SetPoint("BOTTOMRIGHT", -34, 42)
  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(360)
  edit:SetScript("OnEscapePressed", function() shareFrame:Hide() end)
  scroll:SetScrollChild(edit)
  scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
  shareFrame.edit = edit

  shareFrame.import = Button(shareFrame, L["Import"], 120)
  shareFrame.import:SetPoint("BOTTOMRIGHT", -140, 12)
  shareFrame.import:SetScript("OnClick", function()
    local mapID, nameOrErr = FW:ImportRoute(edit:GetText())
    if not mapID then
      FW:Print(nameOrErr)
      return
    end
    FW:Print(format(L["Route imported: %s (%s)."], nameOrErr, FW:ZoneName(mapID)))
    shareFrame:Hide()
    UI:Open(mapID)
  end)

  local close = Button(shareFrame, L["Close"], 120)
  close:SetPoint("BOTTOMRIGHT", -14, 12)
  close:SetScript("OnClick", function() shareFrame:Hide() end)
end

-- text = route à copier ; nil = fenêtre d'import vide.
function UI:ShowShare(text)
  if not shareFrame then buildShare() end
  shareFrame.edit:SetText(text or "")
  shareFrame.import:SetShown(text == nil)
  shareFrame.help:SetText(text and L["Copy this text (Ctrl+C) and send it to another player."]
    or L["Paste a FarmWay route (Ctrl+V), then click Import."])
  shareFrame:Show()
  shareFrame.edit:SetFocus()
  if text then shareFrame.edit:HighlightText() end
end

------------------------------------------------------------------------
-- Panneau principal
------------------------------------------------------------------------

function UI:ShowList()
  self.view = "list"
  newView:Hide()
  listView:Show()
  self:Refresh()
end

function UI:ShowNew()
  self.view = "new"
  FW:SetEditing(false)
  listView:Hide()
  newView:Show()
  newView.name:SetText(defaultName())
  self:RefreshNew()
end

function UI:Refresh()
  if not panel or not panel:IsShown() then return end
  local mapID = displayedMap()
  panel.zone:SetText(FW:ZoneName(mapID))
  if self.view == "list" then refreshList(mapID) end
end

function UI:OnMapChanged()
  if not panel or not panel:IsShown() then return end
  local selMap = FW:GetSelected()
  if FW.editing and selMap ~= displayedMap() then FW:SetEditing(false) end
  if self.view == "new" then
    newView.name:SetText(defaultName())
    self:RefreshNew()
  end
  self:Refresh()
end

function UI:Toggle()
  if panel:IsShown() then
    panel:Hide()
    FW:SetEditing(false)
  else
    panel:Show()
    self:ShowList()
  end
end

-- Ouvre la carte (sur mapID si donné) avec le panneau FarmWay.
function UI:Open(mapID)
  if not WorldMapFrame then return end
  if not WorldMapFrame:IsShown() then ToggleWorldMap() end
  if mapID then WorldMapFrame:SetMapID(mapID) end
  if panel then
    panel:Show()
    self:ShowList()
  end
end

function UI:Build()
  if panel then return end
  local host = WorldMapFrame.ScrollContainer

  local toggle = Button(WorldMapFrame, "FarmWay", 90)
  toggle:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 8, 8)
  toggle:SetFrameLevel(host:GetFrameLevel() + 200)
  toggle:SetScript("OnClick", function() UI:Toggle() end)

  panel = Panel("FarmWayPanel", WorldMapFrame, PANEL_W, PANEL_H)
  panel:SetPoint("BOTTOMLEFT", toggle, "TOPLEFT", 0, 4)
  panel:SetFrameLevel(toggle:GetFrameLevel())
  panel:Hide()

  local title = Text(panel, "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 12, -12)
  title:SetText("FarmWay")
  panel.zone = Text(panel, "GameFontHighlight")
  panel.zone:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
  panel.zone:SetPoint("RIGHT", -30, 0)
  panel.zone:SetWordWrap(false)
  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function() UI:Toggle() end)

  buildList()
  buildNew()
  newView:Hide()
  self.view = "list"

  if WorldMapFrame.OnMapChanged then
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function() UI:OnMapChanged() end)
  end
  WorldMapFrame:HookScript("OnHide", function() FW:SetEditing(false) end)
  FW:RegisterCallback(function() UI:Refresh() end)
end

function UI:Init()
  StaticPopupDialogs.FARMWAY_DELETE = {
    text = L["Delete the route \"%s\"?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
      data = data or self.data
      if data then FW:DeleteRoute(data.mapID, data.name) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
  FW:OnWorldMapReady(function() UI:Build() end)
end
