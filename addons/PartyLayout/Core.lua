-- PartyLayout : chaque cadre du groupe se place et se dimensionne indépendamment des autres.
--
-- Les cadres restent ceux de Blizzard (clics, sorts, auras, addons accrochés comme PartyDebuffs) :
-- l'addon change seulement leur position et leur taille, hors combat. Les positions sont gardées
-- par place dans le groupe (place 1, 2…), séparément pour les cadres style raid et les cadres classiques.
local ADDON, ns = ...
PartyLayout = ns

local VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
                or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "?"

local defaults = {
  enabled = true,
  hideBorder = true,    -- bordure Blizzard autour du groupe, qui n'a plus de sens une fois les cadres séparés
  width = 120,          -- cadres style raid, en pixels
  height = 56,
  scale = 120,          -- cadres classiques, en %
  spacing = 12,         -- espace entre deux cadres quand on les aligne
  horizontal = false,   -- aligner en ligne plutôt qu'en colonne
}

local SLOTS = { compact = 5, classic = 4 }
local LIMITS = { wMin = 40, wMax = 400, hMin = 20, hMax = 200, sMin = 50, sMax = 250 }

local DB
local movers = {}        -- "compact1"… → poignée de déplacement
local hooked = {}        -- cadres Blizzard déjà surveillés
local unlocked = false
local applying = false   -- vrai pendant que l'addon lui-même place un cadre
local pendingCombat = false
local gui

local function Print(s) DEFAULT_CHAT_FRAME:AddMessage("|cff44aaffPartyLayout|r : " .. s) end
local function secret(v) return issecretvalue and issecretvalue(v) or false end
local function round(v) return math.floor(v + 0.5) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-------------------------------------------------------------------------------
-- Cadres Blizzard
-------------------------------------------------------------------------------

-- "compact" : cadres style raid (option « Utiliser des cadres de groupe style raid »).
-- "classic" : cadres de groupe classiques, avec portrait (4 places : ton cadre est le cadre joueur).
local function Style()
  local ok, compact = false, nil
  if EditModeManagerFrame and EditModeManagerFrame.UseRaidStylePartyFrames then
    ok, compact = pcall(EditModeManagerFrame.UseRaidStylePartyFrames, EditModeManagerFrame)
  end
  if not ok and GetCVarBool then compact = GetCVarBool("useCompactPartyFrames") end
  return compact and "compact" or "classic"
end

local function GetFrame(style, i)
  if style == "compact" then return _G["CompactPartyFrameMember" .. i] end
  return (PartyFrame and PartyFrame["MemberFrame" .. i]) or _G["PartyMemberFrame" .. i]
end

-- Échelle du parent du cadre : la taille et la position enregistrées sont converties avec.
local function ParentScale(style, f)
  local p = f and f:GetParent()
  if p then return p:GetEffectiveScale() end
  local c = style == "compact" and CompactPartyFrame or PartyFrame
  return (c and c:GetEffectiveScale()) or UIParent:GetEffectiveScale()
end

-- Taille d'origine d'un cadre classique (on le grossit avec une échelle, pas en l'étirant).
local function ClassicBaseSize(f)
  local w, h = 120, 50
  if f then
    local fw, fh = f:GetWidth(), f:GetHeight()
    if not secret(fw) and fw and fw > 0 then w = fw end
    if not secret(fh) and fh and fh > 0 then h = fh end
  end
  return w, h
end

-------------------------------------------------------------------------------
-- Disposition enregistrée
-- Chaque place : x, y = coin haut-gauche en pixels d'écran depuis le bas-gauche de l'écran ;
-- w, h = taille (style raid) ; scale = taille en % (classique).
-------------------------------------------------------------------------------

local function Layout(style)
  DB.layouts[style] = DB.layouts[style] or {}
  return DB.layouts[style]
end

local function FillSlot(s)
  s.w = s.w or DB.width
  s.h = s.h or DB.height
  s.scale = s.scale or DB.scale
  return s
end

-- Taille d'une place, en pixels d'écran.
local function ScreenSize(style, i, s)
  local f = GetFrame(style, i)
  local ps = ParentScale(style, f)
  if style == "compact" then return s.w * ps, s.h * ps end
  local bw, bh = ClassicBaseSize(f)
  return bw * ps * s.scale / 100, bh * ps * s.scale / 100
end

-- Range toutes les places en colonne (ou en ligne) à partir de la place 1, avec l'espacement choisi.
local function Arrange(style)
  local L = Layout(style)
  local x, y
  if L[1] and L[1].x then
    x, y = L[1].x, L[1].y
  else
    -- Première fois : on part de l'endroit où Blizzard affiche le premier cadre.
    local f = GetFrame(style, 1)
    local left, top = f and f:GetLeft(), f and f:GetTop()
    if f and f:IsVisible() and left and top and not secret(left) and not secret(top) then
      local e = f:GetEffectiveScale()
      x, y = left * e, top * e
    else
      local ui = UIParent:GetEffectiveScale()
      x, y = GetScreenWidth() * ui * 0.03, GetScreenHeight() * ui * 0.70
    end
  end
  local gap = DB.spacing * UIParent:GetEffectiveScale()
  for i = 1, SLOTS[style] do
    local s = FillSlot(L[i] or {})
    L[i] = s
    s.x, s.y = round(x), round(y)
    local w, h = ScreenSize(style, i, s)
    if DB.horizontal then x = x + w + gap else y = y - h - gap end
  end
  DB.free[style] = false
end

local function EnsureLayout(style)
  local L = Layout(style)
  for i = 1, SLOTS[style] do
    if not (L[i] and L[i].x) then Arrange(style) return end
    FillSlot(L[i])
  end
end

-------------------------------------------------------------------------------
-- Application sur les cadres Blizzard
-------------------------------------------------------------------------------

local function DoApply(style, f, s)
  if style == "compact" then f:SetSize(s.w, s.h) else f:SetScale(s.scale / 100) end
  local e = f:GetEffectiveScale()
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", s.x / e, s.y / e)
end

local function ApplyFrame(style, i)
  if InCombatLockdown() then pendingCombat = true return end
  local f = GetFrame(style, i)
  local s = Layout(style)[i]
  if not (f and s and s.x) then return end
  applying = true
  local ok, err = pcall(DoApply, style, f, s)
  applying = false
  if not ok then geterrorhandler()(err) end
end

local function UpdateBorder()
  local b = CompactPartyFrame and CompactPartyFrame.borderFrame
  if b then b:SetAlpha((DB.enabled and DB.hideBorder) and 0 or 1) end
end

local ApplyAll, SetUnlocked

-- Blizzard replace ses cadres à chaque changement de groupe ou passage en mode Édition :
-- on remet notre disposition juste après, une seule fois même si plusieurs appels arrivent d'un coup.
local scheduled = false
local function ApplySoon()
  if scheduled then return end
  scheduled = true
  C_Timer.After(0, function() scheduled = false; ApplyAll() end)
end

local function OnBlizzardChange()
  if applying or not DB or not DB.enabled then return end
  ApplySoon()
end

local function HookFrame(f)
  if not f or hooked[f] then return end
  hooked[f] = true
  hooksecurefunc(f, "SetPoint", OnBlizzardChange)
  hooksecurefunc(f, "SetSize", OnBlizzardChange)
  hooksecurefunc(f, "SetWidth", OnBlizzardChange)
  hooksecurefunc(f, "SetHeight", OnBlizzardChange)
  hooksecurefunc(f, "SetScale", OnBlizzardChange)
  f:HookScript("OnShow", OnBlizzardChange)
end

function ApplyAll()
  if not DB then return end
  UpdateBorder()
  if not DB.enabled then return end
  if InCombatLockdown() then pendingCombat = true return end
  pendingCombat = false
  local style = Style()
  for i = 1, SLOTS[style] do HookFrame(GetFrame(style, i)) end
  -- Pas encore de disposition : on attend que Blizzard affiche le groupe pour partir de sa position.
  local first = GetFrame(style, 1)
  local L = Layout(style)
  if not (L[1] and L[1].x) and not unlocked and not (first and first:IsVisible()) then return end
  EnsureLayout(style)
  for i = 1, SLOTS[style] do ApplyFrame(style, i) end
  if unlocked then SetUnlocked(true) end
end
ns.ApplyAll = ApplyAll

-------------------------------------------------------------------------------
-- Poignées : un rectangle par place, à glisser et à étirer
-------------------------------------------------------------------------------

local function UnitLabel(style, i)
  local f = GetFrame(style, i)
  local unit = f and f.unit
  if not unit and style == "classic" then unit = "party" .. i end
  if not unit or secret(unit) or not UnitExists(unit) then return nil end
  local name = UnitName(unit)
  if not name or secret(name) then return nil end
  return name
end

local function SizeText(m, s)
  if m.style == "compact" then return round(s.w) .. " × " .. round(s.h) end
  return round(s.scale) .. " %"
end

local function PlaceMover(m)
  local s = Layout(m.style)[m.index]
  local w, h = ScreenSize(m.style, m.index, s)
  local e = m:GetEffectiveScale()
  m:ClearAllPoints()
  m:SetSize(math.max(w / e, 16), math.max(h / e, 12))
  m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", s.x / e, s.y / e)
  m.name:SetText(UnitLabel(m.style, m.index) or "")
  m.size:SetText(SizeText(m, s))
end

-- Lit la position (et la taille, pendant un redimensionnement) de la poignée.
local function ReadMover(m, sizing)
  local s = Layout(m.style)[m.index]
  local e = m:GetEffectiveScale()
  local left, top = m:GetLeft(), m:GetTop()
  if not (left and top) then return end
  s.x, s.y = round(left * e), round(top * e)
  if sizing then
    local f = GetFrame(m.style, m.index)
    local ps = ParentScale(m.style, f)
    local sw, sh = m:GetWidth() * e, m:GetHeight() * e
    if m.style == "compact" then
      s.w = clamp(round(sw / ps), LIMITS.wMin, LIMITS.wMax)
      s.h = clamp(round(sh / ps), LIMITS.hMin, LIMITS.hMax)
    else
      local bw = ClassicBaseSize(f)
      s.scale = clamp(round(sw / (bw * ps) * 100), LIMITS.sMin, LIMITS.sMax)
    end
  end
  m.size:SetText(SizeText(m, s))
end

local SyncGui

local function MoverUpdate(m)
  ReadMover(m, m.sizing)
  ApplyFrame(m.style, m.index)
end

local function StopMover(m)
  if not (m.moving or m.sizing) then return end
  m:StopMovingOrSizing()
  m:SetScript("OnUpdate", nil)
  ReadMover(m, m.sizing)
  m.moving, m.sizing = false, false
  DB.free[m.style] = true   -- un cadre bougé seul : les réglages globaux ne réalignent plus le groupe
  ApplyFrame(m.style, m.index)
  PlaceMover(m)
  if SyncGui then SyncGui() end
end

local function MoverOnEnter(m)
  GameTooltip:SetOwner(m, "ANCHOR_RIGHT")
  GameTooltip:AddLine("Place " .. m.index .. " du groupe")
  GameTooltip:AddLine("Glisser : déplacer ce cadre seul", 1, 1, 1)
  GameTooltip:AddLine("Coin en bas à droite : changer sa taille", 1, 1, 1)
  GameTooltip:AddLine("Clic droit : remettre la taille commune", 1, 1, 1)
  GameTooltip:AddLine("Flèches du clavier, survol : déplacer d'un pixel", 1, 1, 1)
  GameTooltip:Show()
end

local function Nudge(m, dx, dy)
  if InCombatLockdown() then return end
  local s = Layout(m.style)[m.index]
  s.x, s.y = s.x + dx, s.y + dy
  DB.free[m.style] = true
  ApplyFrame(m.style, m.index)
  PlaceMover(m)
  if SyncGui then SyncGui() end
end

local function CreateMover(style, i)
  local m = CreateFrame("Frame", nil, UIParent)
  m.style, m.index = style, i
  m:SetFrameStrata("DIALOG")
  m:SetClampedToScreen(true)
  m:SetMovable(true)
  m:SetResizable(true)
  if m.SetResizeBounds then m:SetResizeBounds(16, 12, 900, 500)
  else m:SetMinResize(16, 12); m:SetMaxResize(900, 500) end
  m:EnableMouse(true)
  m:RegisterForDrag("LeftButton")

  local bg = m:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.15, 0.55, 1.0, 0.35)
  local edges = {
    { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
    { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
  }
  for _, e in ipairs(edges) do
    local t = m:CreateTexture(nil, "BORDER")
    t:SetColorTexture(0.4, 0.75, 1.0, 0.9)
    t:SetPoint(e[1])
    t:SetPoint(e[2])
    if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
  end

  local num = m:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  num:SetPoint("CENTER", 0, 4)
  num:SetText(i)
  m.name = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  m.name:SetPoint("TOPLEFT", 4, -3)
  m.size = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  m.size:SetPoint("BOTTOMLEFT", 4, 3)

  m:SetScript("OnDragStart", function(self)
    if InCombatLockdown() then return end
    self.moving = true
    self:StartMoving()
    self:SetScript("OnUpdate", MoverUpdate)
  end)
  m:SetScript("OnDragStop", StopMover)
  m:SetScript("OnMouseUp", function(self, button)
    if button ~= "RightButton" or InCombatLockdown() then return end
    local s = Layout(self.style)[self.index]
    s.w, s.h, s.scale = DB.width, DB.height, DB.scale
    ApplyFrame(self.style, self.index)
    PlaceMover(self)
  end)
  m:SetScript("OnEnter", function(self)
    MoverOnEnter(self)
    self:EnableKeyboard(true)
  end)
  m:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
    self:EnableKeyboard(false)
  end)
  m:SetScript("OnKeyDown", function(self, key)
    local step = IsShiftKeyDown() and 10 or 1
    local d = ({ UP = { 0, step }, DOWN = { 0, -step }, LEFT = { -step, 0 }, RIGHT = { step, 0 } })[key]
    if d then
      self:SetPropagateKeyboardInput(false)
      Nudge(self, d[1], d[2])
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)

  local grip = CreateFrame("Button", nil, m)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or InCombatLockdown() then return end
    m.sizing = true
    m:StartSizing("BOTTOMRIGHT")
    m:SetScript("OnUpdate", MoverUpdate)
  end)
  grip:SetScript("OnMouseUp", function() StopMover(m) end)

  m:Hide()
  return m
end

function SetUnlocked(on)
  unlocked = (on and DB.enabled and not InCombatLockdown()) and true or false
  local style = Style()
  if unlocked then
    EnsureLayout(style)
    for i = 1, SLOTS[style] do
      local key = style .. i
      movers[key] = movers[key] or CreateMover(style, i)
    end
  end
  for _, m in pairs(movers) do
    if unlocked and m.style == style then
      -- Une poignée en cours de glisser n'est ni replacée ni masquée : ça couperait le geste.
      if not (m.moving or m.sizing) then PlaceMover(m) end
      m:Show()
    else
      if m.moving or m.sizing then StopMover(m) end
      m:Hide()
    end
  end
end

-------------------------------------------------------------------------------
-- Réglages groupés
-------------------------------------------------------------------------------

-- Taille commune : appliquée à toutes les places. Si le groupe est encore aligné, on le réaligne
-- pour que les cadres agrandis ne se chevauchent pas ; s'il a été disposé à la main, on n'y touche pas.
local function SetCommonSize(key, v)
  DB[key] = v
  local style = Style()
  EnsureLayout(style)
  local field = ({ width = "w", height = "h", scale = "scale" })[key]
  for _, s in ipairs(Layout(style)) do s[field] = v end
  if not DB.free[style] then Arrange(style) end
  ApplyAll()
end

local function Realign()
  Arrange(Style())
  ApplyAll()
end

local function Reset()
  local enabled = DB.enabled
  for k, v in pairs(defaults) do DB[k] = v end
  DB.enabled = enabled
  local style = Style()
  local first = Layout(style)[1]
  local x, y = first and first.x, first and first.y
  DB.layouts[style] = {}
  if x then Layout(style)[1] = { x = x, y = y } end   -- garde l'endroit où commence le groupe
  Arrange(style)
  ApplyAll()
end

-------------------------------------------------------------------------------
-- Fenêtre de réglages (/plo)
-- Même style que QuestChums et Red Flag : cadre Blizzard, panneaux en retrait, option + description.
-------------------------------------------------------------------------------

local WIN_W = 460
local PANEL_W = WIN_W - 32
local TEXT_W = PANEL_W - 60

local function Panel(parent, y, h)
  local p = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
  p:SetSize(PANEL_W, h)
  p:SetPoint("TOPLEFT", 16, y)
  return p
end

local function Text(parent, value, x, y, w, font)
  local s = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  s:SetPoint("TOPLEFT", x, y)
  if w then s:SetWidth(w) end
  s:SetJustifyH("LEFT")
  s:SetText(value or "")
  return s
end

-- Case à cocher, avec son titre et une ligne de description grise.
local function AddCheck(parent, y, title, desc, get, set)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetPoint("TOPLEFT", 16, y)
  Text(parent, title, 52, y - 4, TEXT_W)
  Text(parent, desc, 52, y - 22, TEXT_W, "GameFontDisableSmall")
  c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); SyncGui() end)
  c.Sync = function(self) self:SetChecked(get()) end
  return c
end

-- Menu déroulant : le menu moderne de Blizzard quand il existe, l'ancien sinon.
local function AddDropdown(parent, x, y, width, choices, get, set)
  local function pick(value) set(value); SyncGui() end
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  if ok and dd and dd.SetupMenu then
    dd:SetPoint("TOPLEFT", x, y)
    dd:SetWidth(width)
    dd:SetupMenu(function(_, root)
      for _, c in ipairs(choices) do
        root:CreateRadio(c[2], function() return get() == c[1] end, function() pick(c[1]) end)
      end
    end)
    dd.Sync = function(self) self:GenerateMenu() end
    return dd
  end
  dd = CreateFrame("Frame", "PartyLayoutAlignDropdown", parent, "UIDropDownMenuTemplate")
  dd:SetPoint("TOPLEFT", x - 16, y + 2)
  UIDropDownMenu_SetWidth(dd, width - 24)
  UIDropDownMenu_Initialize(dd, function()
    for _, c in ipairs(choices) do
      local info = UIDropDownMenu_CreateInfo()
      info.text, info.checked = c[2], get() == c[1]
      info.func = function() pick(c[1]) end
      UIDropDownMenu_AddButton(info)
    end
  end)
  dd.Sync = function(self)
    for _, c in ipairs(choices) do
      if get() == c[1] then UIDropDownMenu_SetText(self, c[2]) end
    end
  end
  return dd
end

local function AddSlider(parent, y, text, min, max, suffix, get, set)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetPoint("TOPLEFT", 0, y)
  holder:SetSize(PANEL_W, 44)
  local label = Text(holder, "", 20, 0)
  local s = CreateFrame("Slider", nil, holder)
  s:SetOrientation("HORIZONTAL")
  s:SetSize(PANEL_W - 40, 16)
  s:SetPoint("TOPLEFT", 20, -20)
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  track:SetHeight(6)
  track:SetColorTexture(0.25, 0.25, 0.25, 1)
  s:SetMinMaxValues(min, max)
  s:SetValueStep(1)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  local function ShowValue(v) label:SetText(text .. " : |cffffffff" .. v .. suffix .. "|r") end
  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v + 0.5)
    ShowValue(v)
    if self.syncing or v == get() then return end
    if InCombatLockdown() then self.syncing = true; self:SetValue(get()); self.syncing = false; return end
    set(v)
  end)
  holder.Sync = function()
    s.syncing = true
    s:SetValue(get())
    s.syncing = false
    ShowValue(get())
  end
  return holder
end

local function AddButton(parent, x, y, w, text, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 26)
  b:SetPoint("TOPLEFT", x, y)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

function SyncGui()
  if not gui then return end
  local style = Style()
  for _, w in ipairs(gui.widgets) do w:Sync() end
  gui.compactSliders[1]:SetShown(style == "compact")
  gui.compactSliders[2]:SetShown(style == "compact")
  gui.classicSlider:SetShown(style == "classic")
  -- Cadres classiques : un seul curseur de taille, l'espacement remonte d'un cran.
  local panelH = style == "compact" and 162 or 114
  gui.spacingSlider:SetPoint("TOPLEFT", 0, style == "compact" and -106 or -58)
  gui.sizesPanel:SetHeight(panelH)
  gui:SetHeight(54 + 168 + panelH + 10 + gui.belowHeight + 14)
  gui.styleText:SetText(style == "compact" and "Cadres style raid : 5 places."
                                            or "Cadres classiques : 4 places (ton propre cadre est le cadre joueur).")
  local status
  if not DB.enabled then
    status = "|cffff6666Désactivé|r : les cadres gardent la disposition de Blizzard."
  elseif InCombatLockdown() then
    status = "|cffffcc00En combat|r : les changements attendront la fin du combat."
  elseif DB.free[style] then
    status = "Disposition |cffffffffà la main|r. « Aligner » remet les cadres en "
             .. (DB.horizontal and "ligne" or "colonne") .. " avec l'espacement choisi."
  else
    status = "Disposition |cffffffffalignée|r : la taille et l'espacement replacent tout le groupe."
  end
  gui.status:SetText(status)
end

local function CreateGui()
  gui = CreateFrame("Frame", "PartyLayoutSettings", UIParent, "BasicFrameTemplateWithInset")
  gui:SetPoint("CENTER", 220, 0)
  gui:SetFrameStrata("DIALOG")
  gui:SetClampedToScreen(true)
  gui:SetMovable(true)
  gui:EnableMouse(true)
  gui:RegisterForDrag("LeftButton")
  gui:SetScript("OnDragStart", gui.StartMoving)
  gui:SetScript("OnDragStop", gui.StopMovingOrSizing)
  gui.TitleText:SetText("PartyLayout — Cadres du groupe")
  -- Fermer la fenêtre (croix, Échap ou bouton) verrouille les cadres.
  gui:SetScript("OnHide", function() SetUnlocked(false) end)
  tinsert(UISpecialFrames, "PartyLayoutSettings")

  gui.styleText = Text(gui, "", 22, -34, WIN_W - 100, "GameFontHighlightSmall")
  Text(gui, "v" .. VERSION, WIN_W - 70, -34, 50, "GameFontDisableSmall"):SetJustifyH("RIGHT")

  local w = {}

  -- Panneau « Affichage »
  local y = -54
  local display = Panel(gui, y, 160)
  w[#w + 1] = AddCheck(display, -10, "Disposition libre des cadres du groupe",
    "Chaque cadre se place et se dimensionne indépendamment des autres.",
    function() return DB.enabled end,
    function(v)
      DB.enabled = v
      if v then
        ApplyAll()
        SetUnlocked(true)
      else
        SetUnlocked(false)
        UpdateBorder()
        Print("désactivé : tape /reload pour rendre aux cadres la disposition de Blizzard.")
      end
    end)
  w[#w + 1] = AddCheck(display, -56, "Masquer la bordure autour du groupe",
    "Le cadre Blizzard qui entoure tout le groupe (cadres style raid).",
    function() return DB.hideBorder end,
    function(v) DB.hideBorder = v; UpdateBorder() end)
  Text(display, "Alignement des cadres", 20, -116)
  w[#w + 1] = AddDropdown(display, 210, -110, 180,
    { { "colonne", "En colonne" }, { "ligne", "En ligne" } },
    function() return DB.horizontal and "ligne" or "colonne" end,
    function(v) DB.horizontal = v == "ligne"; Realign() end)
  y = y - 168

  -- Panneau « Taille et espacement »
  local sizes = Panel(gui, y, 162)
  -- Style raid : largeur et hauteur. Classique : une taille en %, au même endroit.
  local width = AddSlider(sizes, -10, "Largeur des cadres", LIMITS.wMin, LIMITS.wMax, " px",
    function() return DB.width end, function(v) SetCommonSize("width", v) end)
  local classic = AddSlider(sizes, -10, "Taille des cadres", LIMITS.sMin, LIMITS.sMax, " %",
    function() return DB.scale end, function(v) SetCommonSize("scale", v) end)
  local height = AddSlider(sizes, -58, "Hauteur des cadres", LIMITS.hMin, LIMITS.hMax, " px",
    function() return DB.height end, function(v) SetCommonSize("height", v) end)
  w[#w + 1] = width
  w[#w + 1] = classic
  w[#w + 1] = height
  gui.compactSliders, gui.classicSlider = { width, height }, classic
  gui.spacingSlider = AddSlider(sizes, -106, "Espace entre les cadres", 0, 100, " px",
    function() return DB.spacing end, function(v) DB.spacing = v; Realign() end)
  w[#w + 1] = gui.spacingSlider
  gui.sizesPanel = sizes

  -- Sous le panneau, dont la hauteur dépend du style : tout est accroché à son bas.
  local below = CreateFrame("Frame", nil, gui)
  below:SetPoint("TOPLEFT", sizes, "BOTTOMLEFT", 0, -10)
  below:SetSize(PANEL_W, 120)
  y = 0
  gui.status = Text(below, "", 6, y, WIN_W - 44, "GameFontHighlightSmall")
  y = y - 34
  Text(below, "Glisse un rectangle bleu pour déplacer ce cadre seul, tire son coin en bas à droite pour "
            .. "changer sa taille. Clic droit : taille commune. Flèches au survol : 1 pixel (Maj : 10).",
       6, y, WIN_W - 44, "GameFontDisableSmall")
  y = y - 44

  local bw = math.floor((WIN_W - 32 - 16) / 3)
  AddButton(below, 0, y, bw, "Aligner", function()
    if InCombatLockdown() then return end
    Realign()
    SyncGui()
  end)
  AddButton(below, 8 + bw, y, bw, "Réinitialiser", function()
    if InCombatLockdown() then return end
    Reset()
    SyncGui()
  end)
  AddButton(below, 16 + 2 * bw, y, bw, "Terminer", function() gui:Hide() end)

  gui.widgets = w
  gui.belowHeight = -y + 26
  gui:SetWidth(WIN_W)
  gui:Hide()
end

local function ToggleGui()
  if not gui then CreateGui() end
  if gui:IsShown() then
    gui:Hide()
    Print("disposition enregistrée.")
  else
    SyncGui()
    gui:Show()
    if InCombatLockdown() then
      Print("en combat : les cadres seront déverrouillés à la fin du combat.")
    else
      ApplyAll()
      SetUnlocked(true)
    end
  end
end

-------------------------------------------------------------------------------
-- Événements
-------------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    PartyLayoutDB = PartyLayoutDB or {}
    DB = PartyLayoutDB
    for k, v in pairs(defaults) do if DB[k] == nil then DB[k] = v end end
    DB.layouts = DB.layouts or {}
    DB.free = DB.free or {}
    self:UnregisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("UI_SCALE_CHANGED")
    self:RegisterEvent("DISPLAY_SIZE_CHANGED")
    if EventRegistry and EventRegistry.RegisterCallback then
      pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", ApplySoon, ns)
    end
    if CompactPartyFrame then CompactPartyFrame:HookScript("OnShow", ApplySoon) end
    if PartyFrame then PartyFrame:HookScript("OnShow", ApplySoon) end
  elseif event == "PLAYER_REGEN_DISABLED" then
    if unlocked then
      SetUnlocked(false)
      Print("combat : cadres verrouillés jusqu'à la fin du combat.")
    end
    SyncGui()
  elseif event == "PLAYER_REGEN_ENABLED" then
    ApplyAll()
    if gui and gui:IsShown() then SetUnlocked(true) end
    SyncGui()
  else
    ApplySoon()
  end
end)

-------------------------------------------------------------------------------
-- Commande /plo
-------------------------------------------------------------------------------

local function Help()
  Print("commandes :")
  Print("  /plo : ouvre les réglages et déverrouille les cadres")
  Print("  /plo aligner : remet les cadres alignés, avec l'espacement choisi")
  Print("  /plo on | off : active ou désactive la disposition libre (" .. (DB.enabled and "active" or "désactivée") .. ")")
  Print("  /plo reset : réglages par défaut")
end

SLASH_PARTYLAYOUT1 = "/plo"
SLASH_PARTYLAYOUT2 = "/partylayout"
SlashCmdList.PARTYLAYOUT = function(msg)
  local cmd = (msg or ""):lower():match("^%s*(%S*)")
  if cmd == "" or cmd == "set" then
    ToggleGui()
    return
  end
  if InCombatLockdown() and cmd ~= "aide" and cmd ~= "help" then
    Print("impossible en combat : réessaie après.")
    return
  end
  if cmd == "aligner" then
    Realign()
    Print("cadres alignés.")
  elseif cmd == "on" then
    DB.enabled = true
    ApplyAll()
    Print("disposition libre activée.")
  elseif cmd == "off" then
    DB.enabled = false
    SetUnlocked(false)
    UpdateBorder()
    Print("désactivé : tape /reload pour rendre aux cadres la disposition de Blizzard.")
  elseif cmd == "reset" then
    Reset()
    Print("réglages par défaut remis.")
  else
    Help()
    return
  end
  SyncGui()
end
