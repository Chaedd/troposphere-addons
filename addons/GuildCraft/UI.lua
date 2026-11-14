-- GuildCraft : la fenêtre. En haut, un onglet par métier ; à gauche, les recettes que la
-- guilde sait faire dans ce métier ; à droite, qui peut faire la recette choisie.
local _, ns = ...
local M = ns.Model

local ROW_HEIGHT = 20
local WIDTH, LIST_WIDTH = 820, 320
local COLORS = { header = "ffffd100", offline = "ff808080", me = "ff66ccff", dim = "ffb0b0b0" }

local function color(c, s) return "|c" .. c .. s .. "|r" end

local function classColor(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  return c and c.colorStr or "ffffffff"
end

local function text(parent, value, font)
  local s = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  s:SetJustifyH("LEFT"); s:SetText(value or "")
  return s
end

local function scroll(parent, width)
  local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 8, -8); sf:SetPoint("BOTTOMRIGHT", -28, 8)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(width, 1)
  sf:SetScrollChild(child)
  return sf, child
end

-- Noms, icônes et liens des recettes. Les objets pas encore connus du jeu arrivent plus tard.
local GetItemInfoFn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemIconFn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local GetSpellLinkFn = (C_Spell and C_Spell.GetSpellLink) or GetSpellLink
local cache, waiting = {}, {}

local function recipe(t)
  local c = cache[t]
  if c then return c end
  local kind, id = M.ParseToken(t)
  if kind == "i" then
    local name, link, quality = GetItemInfoFn(id)
    if name then
      c = { name = name, link = link, quality = quality, icon = GetItemIconFn and GetItemIconFn(id), kind = kind, id = id }
      cache[t] = c
      return c
    end
    waiting[id] = true
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return { name = "Objet n° " .. id, icon = GetItemIconFn and GetItemIconFn(id), kind = kind, id = id, pending = true }
  end
  local name, icon = ns:SpellInfo(id)
  c = { name = name or ("Recette n° " .. id), icon = icon, kind = kind, id = id }
  local ok, link = pcall(GetSpellLinkFn or function() end, id)
  c.link = ok and link or nil
  if name then cache[t] = c end
  return c
end

local itemEvents = CreateFrame("Frame")
itemEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemEvents:SetScript("OnEvent", function(_, _, id)
  if id and waiting[id] then waiting[id] = nil; ns:Changed() end
end)

local function qualityColor(q)
  local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  return c and c.hex and c.hex:gsub("^|c", "") or "ffffffff"
end

-- Recettes connues de la guilde pour un métier, avec leurs artisans.
function ns:GuildRecipes(p, filter)
  local byToken, list = {}, {}
  local members = self.guild and self.guild.members or {}
  local now = GetServerTime()
  for key, r in pairs(self.roster) do
    local m = members[key]
    local pr = m and m.profs and m.profs[p]
    local me = key == self.playerKey
    if pr and pr.r and (r.online or me or self.options.showOffline) then
      local crafter = {
        name = r.name, class = r.class, online = r.online, me = me,
        rank = pr.rank, max = pr.max, age = now - (m.t or now),
      }
      for t in pairs(pr.r) do
        local e = byToken[t]
        if not e then
          e = { token = t, crafters = {} }
          byToken[t] = e
          list[#list + 1] = e
        end
        e.crafters[#e.crafters + 1] = crafter
      end
    end
  end
  local out = {}
  for _, e in ipairs(list) do
    e.info = recipe(e.token)
    e.sortName = e.info.name:lower()
    if not filter or e.sortName:find(filter, 1, true) then out[#out + 1] = e end
  end
  table.sort(out, function(a, b)
    if a.sortName ~= b.sortName then return a.sortName < b.sortName end
    return a.token < b.token
  end)
  return out
end

-- Métiers pour lesquels la guilde a au moins une recette.
function ns:GuildProfessions()
  local count = {}
  local members = self.guild and self.guild.members or {}
  for key, r in pairs(self.roster) do
    local m = members[key]
    if m and m.profs and (r.online or key == self.playerKey or self.options.showOffline) then
      for p, pr in pairs(m.profs) do
        if self.ProfessionsByID[p] and pr.r and next(pr.r) then count[p] = (count[p] or 0) + 1 end
      end
    end
  end
  local list = {}
  for p, n in pairs(count) do list[#list + 1] = { p = p, crafters = n, name = self:ProfessionName(p) } end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

local function crafterLine(e)
  local name = color(e.online and classColor(e.class) or COLORS.offline, e.name)
  if e.me then name = name .. color(COLORS.me, " (toi)") end
  local parts = {}
  if e.rank and e.rank > 0 then parts[#parts + 1] = e.rank .. (e.max and e.max > 0 and (" / " .. e.max) or "") end
  if not e.online then parts[#parts + 1] = color(COLORS.offline, "hors ligne, vu " .. M.Age(e.age)) end
  return "   " .. name .. (#parts > 0 and ("  —  " .. table.concat(parts, " · ")) or "")
end

local function sortCrafters(list)
  table.sort(list, function(a, b)
    if a.online ~= b.online then return a.online end
    if (a.rank or 0) ~= (b.rank or 0) then return (a.rank or 0) > (b.rank or 0) end
    return a.name < b.name
  end)
end

local function showTooltip(owner, info)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local ok
  if info.kind == "i" then
    ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. info.id)
  elseif GameTooltip.SetSpellByID then
    ok = pcall(GameTooltip.SetSpellByID, GameTooltip, info.id)
  else
    ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. info.id)
  end
  if not ok or GameTooltip:NumLines() == 0 then GameTooltip:AddLine(info.name, 1, 1, 1) end
  GameTooltip:AddLine("Maj-clic : lier dans la discussion.", .6, .6, .6)
  GameTooltip:Show()
end

local function linkInChat(info)
  if not info.link then return end
  if ChatEdit_InsertLink then ChatEdit_InsertLink(info.link) end
end

function ns:RefreshDetail(e)
  local f = self.window
  if not e then
    f.recipeIcon:Hide()
    f.recipeTitle:SetText(self.guild and "Aucune recette" or "Hors guilde")
    f.recipeInfo:SetText("")
    local help
    if not self.scope then
      help = "Rejoins une guilde pour voir les recettes de ses membres."
    elseif f.search:GetText() ~= "" then
      help = "Aucune recette ne correspond à ta recherche."
    else
      help = "Personne n'a encore partagé de recettes.\n\n"
        .. "Ouvre une fois la fenêtre de chacun de tes métiers : tes recettes sont alors envoyées "
        .. "aux membres de ta guilde qui ont aussi GuildCraft, et les leurs apparaissent ici."
    end
    f.detail:SetText(color(COLORS.dim, help))
  else
    local info = e.info
    f.recipeIcon:SetTexture(info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    f.recipeIcon:Show()
    f.recipeTitle:SetText(info.kind == "i" and color(qualityColor(info.quality), info.name) or info.name)
    f.recipeInfo:SetText(self:ProfessionName(f.selectedProf) .. " · "
      .. #e.crafters .. (#e.crafters > 1 and " artisans" or " artisan"))
    sortCrafters(e.crafters)
    local online, offline = {}, {}
    for _, c in ipairs(e.crafters) do
      local list = c.online and online or offline
      list[#list + 1] = crafterLine(c)
    end
    local lines = { color(COLORS.header, "Peuvent la faire maintenant (" .. #online .. ")") }
    if #online == 0 then lines[#lines + 1] = color(COLORS.dim, "   Personne n'est connecté.") end
    for _, l in ipairs(online) do lines[#lines + 1] = l end
    if #offline > 0 then
      lines[#lines + 1] = " "
      lines[#lines + 1] = color(COLORS.offline, "Hors ligne (" .. #offline .. ")")
      for _, l in ipairs(offline) do lines[#lines + 1] = l end
    end
    f.detail:SetText(table.concat(lines, "\n"))
  end
  f.detailChild:SetHeight(math.max(1, f.detail:GetStringHeight() + 8))
end

local function acquireRow(f, i)
  local row = f.rows[i]
  if row then return row end
  row = CreateFrame("Button", nil, f.listChild)
  row:SetSize(f.listChild:GetWidth(), ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.selected = row:CreateTexture(nil, "BACKGROUND")
  row.selected:SetAllPoints(); row.selected:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  row.selected:SetBlendMode("ADD"); row.selected:SetVertexColor(1, .82, 0, .6)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16); row.icon:SetPoint("LEFT", 4, 0); row.icon:SetTexCoord(.08, .92, .08, .92)
  row.label = text(row, "")
  row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0); row.label:SetPoint("RIGHT", -34, 0); row.label:SetWordWrap(false)
  row.count = text(row, "", "GameFontHighlightSmall")
  row.count:SetPoint("RIGHT", -4, 0); row.count:SetJustifyH("RIGHT")
  row:SetScript("OnClick", function(self)
    if not self.entry then return end
    if IsShiftKeyDown() then linkInChat(self.entry.info); return end
    f.selected[f.selectedProf] = self.entry.token
    ns:RefreshUI()
  end)
  row:SetScript("OnEnter", function(self) if self.entry then showTooltip(self, self.entry.info) end end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.rows[i] = row
  return row
end

local function acquireTab(f, i)
  local tab = f.tabs[i]
  if tab then return tab end
  tab = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  tab:SetHeight(24)
  tab.icon = tab:CreateTexture(nil, "OVERLAY")
  tab.icon:SetSize(16, 16); tab.icon:SetPoint("LEFT", 6, 0); tab.icon:SetTexCoord(.08, .92, .08, .92)
  tab:SetScript("OnClick", function(self)
    f.selectedProf = self.prof
    ns:RefreshUI()
  end)
  f.tabs[i] = tab
  return tab
end

-- Onglets sur une ou plusieurs lignes ; renvoie la hauteur occupée.
local function layoutTabs(f, profs)
  local x, y, maxX = 14, -30, WIDTH - 14
  for i, info in ipairs(profs) do
    local tab = acquireTab(f, i)
    tab.prof = info.p
    tab:SetText("      " .. info.name .. " (" .. info.crafters .. ")")
    tab.icon:SetTexture(ns:ProfessionIcon(info.p))
    local w = (tab:GetFontString() and tab:GetFontString():GetStringWidth() or 100) + 20
    if x + w > maxX and x > 14 then x, y = 14, y - 26 end
    tab:ClearAllPoints(); tab:SetPoint("TOPLEFT", x, y); tab:SetWidth(w)
    if info.p == f.selectedProf then tab:LockHighlight() else tab:UnlockHighlight() end
    tab:Show()
    x = x + w + 4
  end
  for j = #profs + 1, #f.tabs do f.tabs[j]:Hide() end
  return -y + (#profs > 0 and 26 or 0)
end

function ns:RefreshUI()
  local f = self.window
  if not f or not f:IsShown() then return end

  local profs = self:GuildProfessions()
  local valid = false
  for _, info in ipairs(profs) do if info.p == f.selectedProf then valid = true end end
  if not valid then f.selectedProf = profs[1] and profs[1].p end

  local top = layoutTabs(f, profs) + 4
  f.left:SetPoint("TOPLEFT", 14, -top)
  f.right:SetPoint("TOPLEFT", f.left, "TOPRIGHT", 8, 0)

  local filter = f.search:GetText():lower():match("^%s*(.-)%s*$")
  local recipes = f.selectedProf and self:GuildRecipes(f.selectedProf, filter ~= "" and filter or nil) or {}
  local selectedToken = f.selectedProf and f.selected[f.selectedProf]
  local selected
  for _, e in ipairs(recipes) do if e.token == selectedToken then selected = e end end
  if not selected and recipes[1] then
    selected = recipes[1]
    if f.selectedProf then f.selected[f.selectedProf] = selected.token end
  end

  for i, e in ipairs(recipes) do
    local row = acquireRow(f, i)
    row.entry = e
    row.icon:SetTexture(e.info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local name = e.info.kind == "i" and color(qualityColor(e.info.quality), e.info.name) or e.info.name
    row.label:SetText(name)
    local online = 0
    for _, c in ipairs(e.crafters) do if c.online then online = online + 1 end end
    row.count:SetText(color(online > 0 and "ff40ff40" or COLORS.offline, online) .. color(COLORS.dim, "/" .. #e.crafters))
    row.selected:SetShown(e == selected)
    row:Show()
  end
  for j = #recipes + 1, #f.rows do f.rows[j]:Hide(); f.rows[j].entry = nil end
  f.listChild:SetHeight(math.max(1, #recipes * ROW_HEIGHT))
  f.listInfo:SetText(f.selectedProf and (#recipes .. " recette" .. (#recipes > 1 and "s" or "")) or "")
  self:RefreshDetail(selected)

  local online, equipped = 0, 0
  for key, r in pairs(self.roster) do
    if r.online and key ~= self.playerKey then
      online = online + 1
      if self.heard[key] then equipped = equipped + 1 end
    end
  end
  if not self.scope then
    f.status:SetText("Hors guilde.")
  else
    f.status:SetText("Équipés : " .. equipped .. " sur " .. online .. " connectés"
      .. (self.lastRequestTime and (" · demande à " .. date("%H:%M", self.lastRequestTime)) or ""))
  end
  f.refresh:SetEnabled(self.scope ~= nil)
end

function ns:CreateUI()
  local f = CreateFrame("Frame", "GuildCraftWindow", UIParent, "BasicFrameTemplateWithInset")
  self.window = f
  f:SetSize(WIDTH, 540); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.TitleText:SetText("GuildCraft — Les recettes de ta guilde")
  tinsert(UISpecialFrames, "GuildCraftWindow")
  f.rows, f.tabs, f.selected = {}, {}, {}

  f.left = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
  f.left:SetPoint("TOPLEFT", 14, -60); f.left:SetPoint("BOTTOMLEFT", 14, 54); f.left:SetWidth(LIST_WIDTH)
  f.listScroll, f.listChild = scroll(f.left, LIST_WIDTH - 36)
  f.listInfo = text(f, "", "GameFontDisableSmall")
  f.listInfo:SetPoint("TOPLEFT", f.left, "BOTTOMLEFT", 4, -2)

  f.right = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
  f.right:SetPoint("TOPLEFT", f.left, "TOPRIGHT", 8, 0); f.right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 54)
  f.recipeIcon = f.right:CreateTexture(nil, "ARTWORK")
  f.recipeIcon:SetSize(32, 32); f.recipeIcon:SetPoint("TOPLEFT", 10, -10)
  f.recipeTitle = text(f.right, "", "GameFontNormalLarge")
  f.recipeTitle:SetPoint("TOPLEFT", 50, -10); f.recipeTitle:SetPoint("RIGHT", -12, 0); f.recipeTitle:SetWordWrap(false)
  f.recipeInfo = text(f.right, "", "GameFontDisableSmall")
  f.recipeInfo:SetPoint("TOPLEFT", f.recipeTitle, "BOTTOMLEFT", 0, -4)
  local hover = CreateFrame("Frame", nil, f.right)
  hover:SetPoint("TOPLEFT", 8, -8); hover:SetSize(36, 36)
  hover:SetScript("OnEnter", function(self)
    local token = f.selectedProf and f.selected[f.selectedProf]
    if token and f.recipeIcon:IsShown() then showTooltip(self, recipe(token)) end
  end)
  hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local holder = CreateFrame("Frame", nil, f.right)
  holder:SetPoint("TOPLEFT", 0, -50); holder:SetPoint("BOTTOMRIGHT")
  local detailWidth = WIDTH - 14 - 14 - LIST_WIDTH - 8 - 36
  f.detailScroll, f.detailChild = scroll(holder, detailWidth)
  f.detail = text(f.detailChild, "")
  f.detail:SetPoint("TOPLEFT", 4, -4); f.detail:SetWidth(detailWidth - 4); f.detail:SetSpacing(3)

  f.refresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.refresh:SetSize(150, 26); f.refresh:SetPoint("BOTTOMLEFT", 16, 18)
  f.refresh:SetText("Demander à la guilde")
  f.refresh:SetScript("OnClick", function() ns:RequestAll(true) end)

  f.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  f.search:SetSize(160, 20); f.search:SetPoint("LEFT", f.refresh, "RIGHT", 18, 0); f.search:SetAutoFocus(false)
  local placeholder = text(f.search, "Rechercher…", "GameFontDisableSmall")
  placeholder:SetPoint("LEFT", 2, 0)
  f.search:SetScript("OnTextChanged", function(self)
    placeholder:SetShown(self:GetText() == "")
    ns:RefreshUI()
  end)
  f.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  f.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

  local offline = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  offline:SetSize(26, 26); offline:SetPoint("LEFT", f.search, "RIGHT", 12, 0)
  offline:SetChecked(self.options.showOffline)
  offline:SetScript("OnClick", function(b) ns.options.showOffline = b:GetChecked() and true or false; ns:RefreshUI() end)
  local offlineLabel = text(f, "Membres hors ligne", "GameFontHighlightSmall")
  offlineLabel:SetPoint("LEFT", offline, "RIGHT", 2, 0)

  f.status = text(f, "", "GameFontDisableSmall")
  f.status:SetPoint("BOTTOMRIGHT", -18, 24); f.status:SetJustifyH("RIGHT")

  f:SetScript("OnShow", function()
    ns:RefreshUI()
    if ns.scope and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
  end)
  f:Hide()
end

function ns:Toggle()
  if not self.window then self:CreateUI() end
  if self.window:IsShown() then
    self.window:Hide()
  else
    self.window:Show()
    if not self.lastRequest or GetTime() - self.lastRequest > 60 then self:RequestAll() end
  end
end
