-- QuestChums : la fenêtre. À gauche, les quêtes du journal ; à droite, la guilde pour
-- la quête choisie : qui l'a aussi, qui peut la faire, qui ne l'a pas.
local _, ns = ...
local M = ns.Model

local ROW_HEIGHT = 22
local COLORS = {
  has = "ff40ff40", can = "ffffd100", none = "ffb0b0b0", silent = "ff808080",
  header = "ffffd100", offline = "ff808080",
}

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

-- Membres de la guilde classés pour une quête.
function ns:Classify(id)
  local out = { has = {}, can = {}, none = {}, silent = {} }
  local now = GetServerTime()
  local members = self.guild and self.guild.members or {}
  for key, r in pairs(self.roster) do
    local e = members[key] and members[key].q and members[key].q[id]
    local entry = { name = r.name, level = r.level, class = r.class, online = r.online }
    if e then
      entry.s, entry.age = e.s, now - (e.t or now)
      local cat = M.Category(e.s)
      if cat and (r.online or self.options.showOffline) then
        local list = cat == "not" and out.none or out[cat]
        list[#list + 1] = entry
      end
    elseif r.online then
      out.silent[#out.silent + 1] = entry
    end
  end
  local function byName(a, b)
    if a.online ~= b.online then return a.online end
    return a.name < b.name
  end
  table.sort(out.has, function(a, b)
    local pa, pb = M.ProgressValue(a.s), M.ProgressValue(b.s)
    if pa ~= pb then return pa > pb end
    return byName(a, b)
  end)
  table.sort(out.can, byName); table.sort(out.none, byName); table.sort(out.silent, byName)
  return out
end

local DETAIL = { D = "déjà faite", X = "quête précédente pas faite", N = "ne sait pas s'il peut la prendre" }

local function memberLine(e)
  local name = color(e.online and classColor(e.class) or COLORS.offline, e.name)
  local parts = {}
  if e.level then parts[#parts + 1] = "niv. " .. e.level end
  if e.s == "HR" then parts[#parts + 1] = color(COLORS.has, "prête à rendre")
  elseif e.s and e.s:match("^H") then parts[#parts + 1] = M.ProgressValue(e.s) .. " %"
  elseif DETAIL[e.s] then parts[#parts + 1] = DETAIL[e.s] end
  if not e.online then parts[#parts + 1] = color(COLORS.offline, "hors ligne, " .. M.Age(e.age)) end
  return "   " .. name .. (#parts > 0 and ("  —  " .. table.concat(parts, " · ")) or "")
end

local function section(lines, title, c, list, empty)
  lines[#lines + 1] = color(c, title .. " (" .. #list .. ")")
  if #list == 0 then lines[#lines + 1] = color(COLORS.silent, "   " .. empty) end
  for _, e in ipairs(list) do lines[#lines + 1] = memberLine(e) end
  lines[#lines + 1] = " "
end

function ns:RefreshDetail()
  local f = self.window
  local q = f.selectedQuest
  if not q then
    f.questTitle:SetText("Aucune quête")
    f.questInfo:SetText("")
    f.detail:SetText(self.scope and "Ton journal de quêtes est vide." or "Rejoins une guilde pour comparer tes quêtes.")
  else
    f.questTitle:SetText(q.title)
    local info = {}
    if q.level and q.level > 0 then info[#info + 1] = "Niveau " .. q.level end
    if q.header then info[#info + 1] = q.header end
    f.questInfo:SetText(table.concat(info, " · "))
    local c = self:Classify(q.id)
    local lines = {}
    section(lines, "L'a aussi", COLORS.has, c.has, "Personne pour l'instant.")
    section(lines, "Peut la faire", COLORS.can, c.can, "Personne, à notre connaissance.")
    section(lines, "Ne l'a pas", COLORS.none, c.none, "Personne.")
    lines[#lines + 1] = color(COLORS.silent, "Connectés sans réponse (" .. #c.silent .. ")")
    if #c.silent > 0 then
      local names = {}
      for _, e in ipairs(c.silent) do names[#names + 1] = e.name end
      lines[#lines + 1] = color(COLORS.silent, "   " .. table.concat(names, ", "))
      lines[#lines + 1] = color(COLORS.silent, "   QuestChums n'est pas installé chez eux, ou ils n'ont pas encore répondu.")
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
  row.label = text(row, "")
  row.label:SetPoint("LEFT", 6, 0); row.label:SetPoint("RIGHT", -62, 0); row.label:SetWordWrap(false)
  row.counts = text(row, "", "GameFontHighlightSmall")
  row.counts:SetPoint("RIGHT", -4, 0); row.counts:SetJustifyH("RIGHT")
  row:SetScript("OnClick", function(self)
    if self.quest then f.selectedID = self.quest.id; ns:RefreshUI() end
  end)
  row:SetScript("OnEnter", function(self)
    if not self.quest then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.quest.title, 1, 1, 1, true)
    GameTooltip:AddLine(color(COLORS.has, self.has .. " l'ont aussi") .. "   " .. color(COLORS.can, self.can .. " peuvent la faire"))
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.rows[i] = row
  return row
end

function ns:RefreshUI()
  local f = self.window
  if not f or not f:IsShown() then return end
  local quests = self:MyQuests()
  local i, header = 0, nil
  f.selectedQuest = nil
  for _, q in ipairs(quests) do
    if q.header and q.header ~= header then
      header = q.header
      i = i + 1
      local row = acquireRow(f, i)
      row.quest = nil
      row:EnableMouse(false); row.selected:Hide()
      row.label:SetText(color(COLORS.header, header)); row.counts:SetText("")
      row:Show()
    end
    i = i + 1
    local row = acquireRow(f, i)
    local c = self:Classify(q.id)
    row.quest, row.has, row.can = q, #c.has, #c.can
    row:EnableMouse(true)
    row.label:SetText("  " .. q.title)
    row.counts:SetText(color(COLORS.has, #c.has) .. "  " .. color(COLORS.can, #c.can))
    if not f.selectedID then f.selectedID = q.id end
    if q.id == f.selectedID then f.selectedQuest = q end
    row.selected:SetShown(q.id == f.selectedID)
    row:Show()
  end
  for j = i + 1, #f.rows do f.rows[j]:Hide(); f.rows[j].quest = nil end
  if not f.selectedQuest and quests[1] then
    f.selectedID = quests[1].id
    return self:RefreshUI()
  end
  f.listChild:SetHeight(math.max(1, i * ROW_HEIGHT))
  self:RefreshDetail()

  local online, equipped = 0, 0
  local members = self.guild and self.guild.members or {}
  for key, r in pairs(self.roster) do
    if r.online then
      online = online + 1
      if members[key] then equipped = equipped + 1 end
    end
  end
  if not self.scope then
    f.status:SetText("Hors guilde : rien à comparer.")
  else
    f.status:SetText("Équipés : " .. equipped .. " sur " .. online .. " connectés"
      .. (self.lastRequestTime and (" · demande à " .. date("%H:%M", self.lastRequestTime)) or ""))
  end
  f.refresh:SetEnabled(self.scope ~= nil)
end

function ns:CreateUI()
  local f = CreateFrame("Frame", "QuestChumsWindow", UIParent, "BasicFrameTemplateWithInset")
  self.window = f
  f:SetSize(780, 500); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.TitleText:SetText("QuestChums — Tes quêtes et ta guilde")
  tinsert(UISpecialFrames, "QuestChumsWindow")
  f.rows = {}

  local left = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
  left:SetPoint("TOPLEFT", 14, -34); left:SetSize(300, 412)
  local legend = text(left, color(COLORS.has, "l'ont") .. "  " .. color(COLORS.can, "peuvent"), "GameFontHighlightSmall")
  legend:SetPoint("BOTTOMRIGHT", left, "TOPRIGHT", -30, 2)
  f.listScroll, f.listChild = scroll(left, 264)

  local right = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0); right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 54)
  f.questTitle = text(right, "", "GameFontNormalLarge")
  f.questTitle:SetPoint("TOPLEFT", 12, -10); f.questTitle:SetPoint("RIGHT", -12, 0); f.questTitle:SetWordWrap(false)
  f.questInfo = text(right, "", "GameFontDisableSmall")
  f.questInfo:SetPoint("TOPLEFT", f.questTitle, "BOTTOMLEFT", 0, -4)
  local holder = CreateFrame("Frame", nil, right)
  holder:SetPoint("TOPLEFT", 0, -46); holder:SetPoint("BOTTOMRIGHT")
  f.detailScroll, f.detailChild = scroll(holder, 400)
  f.detail = text(f.detailChild, "")
  f.detail:SetPoint("TOPLEFT", 4, -4); f.detail:SetWidth(396); f.detail:SetSpacing(3)

  f.refresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.refresh:SetSize(140, 26); f.refresh:SetPoint("BOTTOMLEFT", 16, 18)
  f.refresh:SetText("Demander à la guilde")
  f.refresh:SetScript("OnClick", function() ns:RequestStatus(true) end)

  local offline = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  offline:SetSize(26, 26); offline:SetPoint("LEFT", f.refresh, "RIGHT", 12, 0)
  offline:SetChecked(self.options.showOffline)
  offline:SetScript("OnClick", function(b) ns.options.showOffline = b:GetChecked() and true or false; ns:RefreshUI() end)
  local offlineLabel = text(f, "Membres hors ligne (dernier état connu)", "GameFontHighlightSmall")
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
    -- Ouvrir la fenêtre relance une demande si la dernière date d'au moins une minute.
    if not self.lastRequest or GetTime() - self.lastRequest > 60 then self:RequestStatus() end
  end
end
