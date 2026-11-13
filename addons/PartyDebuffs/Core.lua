-- PartyDebuffs : une rangée d'icônes de debuffs sous chaque cadre de membre du groupe.
local ADDON, ns = ...
PartyDebuffs = ns

local defaults = {
  size = 20,             -- taille d'une icône, en pixels
  position = "dessous",  -- "dessous" ou "droite" du cadre
  onlyDispellable = false,
  showTimer = true,
  showPlayer = true,     -- tes propres debuffs, dans un cadre accroché à ton cadre joueur
  showDebuffs = true,
  showBuffs = false,     -- buffs affichés après les debuffs
  -- Cadre de tes debuffs : coin haut-gauche, décalé par rapport au coin bas-gauche du cadre joueur.
  boxX = 0, boxY = -4, boxW = 188, boxH = 20,
}

local DB
local rows = {}          -- cadre Blizzard → rangée d'icônes
local testMode = false
local setMode = false    -- /pdb : cadre de tes debuffs déplaçable et redimensionnable
local box                -- cadre invisible qui contient tes debuffs
local GAP = 4            -- espace entre deux icônes

-- Couleur de la bordure selon le type de debuff.
local TYPE_COLORS = {
  Magic   = { 0.20, 0.60, 1.00 },
  Curse   = { 0.60, 0.00, 1.00 },
  Disease = { 0.60, 0.40, 0.00 },
  Poison  = { 0.00, 0.60, 0.00 },
  none    = { 0.80, 0.00, 0.00 },
}

-- Faux debuffs de /pdb test, dans l'ordre d'affichage réel : dissipables, puis les autres.
local TEST_AURAS = {
  { kind = "dispel", label = "Magie, dissipable",        icon = "Interface\\Icons\\Spell_Frost_FrostNova",          dispelName = "Magic",  applications = 1, duration = 8 },
  { kind = "dispel", label = "Poison, dissipable",       icon = "Interface\\Icons\\Spell_Nature_CorrosiveBreath",   dispelName = "Poison", applications = 3, duration = 12 },
  { kind = "other",  label = "Âme affaiblie, toujours affichée", always = true, icon = "Interface\\Icons\\Spell_Holy_AshesToAshes", applications = 1, duration = 15 },
  { kind = "other",  label = "Malédiction, non dissipable", icon = "Interface\\Icons\\Spell_Shadow_CurseOfSargeras", dispelName = "Curse",  applications = 1, duration = 30 },
  { kind = "other",  label = "non dissipable",           icon = "Interface\\Icons\\Spell_Shadow_AbominationExplosion", applications = 1, duration = 0 },
  { kind = "buff",   label = "buff",                     icon = "Interface\\Icons\\Spell_Holy_WordFortitude",       applications = 1, duration = 0 },
  { kind = "buff",   label = "buff",                     icon = "Interface\\Icons\\Spell_Nature_Regeneration",      applications = 1, duration = 25 },
}

local function Print(s) DEFAULT_CHAT_FRAME:AddMessage("|cffcc4444PartyDebuffs|r : " .. s) end

-- Valeur protégée par le jeu (en combat, sur les clients récents) : on ne peut ni la comparer ni calculer avec.
-- Même « if v » est interdit sur une valeur protégée : toujours tester secret() AVANT la valeur.
local function secret(v) return issecretvalue and issecretvalue(v) or false end
-- La valeur si elle est lisible, sinon nil.
local function plain(v) if secret(v) then return nil end return v end

-------------------------------------------------------------------------------
-- Lecture des debuffs
-------------------------------------------------------------------------------

-- Lit un debuff (filtre "HARMFUL…") ou un buff (filtre "HELPFUL…") avec les anciennes fonctions.
local function GetDebuff(unit, index, filter)
  local read = UnitAura or (filter:find("HELPFUL") and UnitBuff or UnitDebuff)
  if read then
    local name, icon, count, dispelType, duration, expirationTime, _, _, _, spellId = read(unit, index, filter)
    if name then
      return { name = name, icon = icon, applications = count, dispelName = dispelType,
               duration = duration, expirationTime = expirationTime, spellId = spellId }
    end
  end
end

-- Toutes les auras d'une unité pour un filtre : liste de { a = données, index = position ou nil }.
-- Sur les clients récents, en combat en instance, le jeu interdit de lire les auras des autres
-- une par une (GetAuraDataByIndex lève une erreur) : on passe alors par leurs identifiants d'aura.
-- Tout est protégé par pcall : si le jeu refuse tout, la liste est vide, sans erreur Lua.
local function AuraList(unit, filter)
  local list = {}
  local api = C_UnitAuras
  if not (api and api.GetAuraDataByIndex) then
    for index = 1, 40 do
      local a = GetDebuff(unit, index, filter)
      if not a then break end
      list[#list + 1] = { a = a, index = index }
    end
    return list
  end

  local blocked = false
  for index = 1, 40 do
    local ok, a = pcall(api.GetAuraDataByIndex, unit, index, filter)
    if not ok then blocked = true; break end
    if not a then break end
    list[#list + 1] = { a = a, index = index }
  end
  if not blocked then return list end

  list = {}
  if api.GetUnitAuraInstanceIDs and api.GetAuraDataByAuraInstanceID then
    local ok, ids = pcall(api.GetUnitAuraInstanceIDs, unit, filter)
    if ok and type(ids) == "table" then
      for _, id in ipairs(ids) do
        local ok2, a = pcall(api.GetAuraDataByAuraInstanceID, unit, id)
        if ok2 and type(a) == "table" then list[#list + 1] = { a = a } end
      end
    end
  end
  return list
end

-- Debuffs toujours affichés, même avec /pdb dissipables et au-delà de la taille de la grille.
local ALWAYS = {
  [6788] = true,   -- Âme affaiblie (Weakened Soul), après Mot de pouvoir : Bouclier du prêtre
}

local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

-- Noms traduits dans la langue du client, utilisés si l'identifiant du sort n'est pas lisible.
local ALWAYS_NAMES = {}
for id in pairs(ALWAYS) do
  local name = SpellName(id)
  if name then ALWAYS_NAMES[name] = true end
end

local function IsAlways(a)
  local id = plain(a.spellId)
  if id then return ALWAYS[id] or false end
  local name = plain(a.name)
  if name then return ALWAYS_NAMES[name] or false end
  return false
end

-- Cherche directement les debuffs de la liste ALWAYS par leur identifiant de sort.
-- En combat, sur les clients récents, le nom et l'identifiant des auras lues une par une
-- sont protégés : on ne peut plus reconnaître Âme affaiblie en parcourant la liste.
-- Demander au jeu « cette unité a-t-elle le sort 6788 ? » marche encore, car c'est nous qui donnons l'identifiant.
local function FindAlways(unit)
  local found = {}
  local api = C_UnitAuras
  if not api then return found end
  for id in pairs(ALWAYS) do
    local a
    if unit == "player" and api.GetPlayerAuraBySpellID then
      local ok, r = pcall(api.GetPlayerAuraBySpellID, id)
      if ok then a = r end
    end
    if not a and api.GetUnitAuraBySpellID then
      local ok, r = pcall(api.GetUnitAuraBySpellID, unit, id)
      if ok then a = r end
    end
    if a then found[#found + 1] = a end
  end
  return found
end

-- Identifie un debuff pour ne pas l'afficher deux fois (il ressort dans les deux listes : dissipables et tous).
local function AuraKey(a)
  local id = plain(a.auraInstanceID)
  if id then return id end
  local name, expiration = plain(a.name), plain(a.expirationTime)
  if name and expiration then
    return name .. ":" .. expiration
  end
end

-------------------------------------------------------------------------------
-- Icônes
-------------------------------------------------------------------------------

local function SetBorderSize(b, t)
  if b.borderSize == t then return end
  b.borderSize = t
  b.border:ClearAllPoints()
  b.border:SetPoint("TOPLEFT", -t, t)
  b.border:SetPoint("BOTTOMRIGHT", t, -t)
end

local function IconOnEnter(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
  local buff = self.filter and self.filter:find("HELPFUL")
  if self.test then
    GameTooltip:SetText("Test : " .. self.test)
  elseif buff then
    if self.auraInstanceID and GameTooltip.SetUnitBuffByAuraInstanceID then
      GameTooltip:SetUnitBuffByAuraInstanceID(self.unit, self.auraInstanceID, self.filter)
    else
      GameTooltip:SetUnitBuff(self.unit, self.index, self.filter)
    end
  elseif self.auraInstanceID and GameTooltip.SetUnitDebuffByAuraInstanceID then
    GameTooltip:SetUnitDebuffByAuraInstanceID(self.unit, self.auraInstanceID, self.filter)
  elseif self.index then
    GameTooltip:SetUnitDebuff(self.unit, self.index, self.filter)
  else
    return
  end
  GameTooltip:Show()
end

local function CreateIcon(row)
  local b = CreateFrame("Frame", nil, row)
  b.glow = b:CreateTexture(nil, "BACKGROUND", nil, -1)
  b.glow:SetPoint("TOPLEFT", -4, 4)
  b.glow:SetPoint("BOTTOMRIGHT", 4, -4)
  b.glow:SetColorTexture(1, 1, 1, 0.6)
  b.glow:Hide()
  b.pulse = b.glow:CreateAnimationGroup()
  b.pulse:SetLooping("BOUNCE")
  local fade = b.pulse:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0.15)
  fade:SetDuration(0.6)

  b.border = b:CreateTexture(nil, "BACKGROUND")
  b.border:SetColorTexture(1, 1, 1)
  SetBorderSize(b, 1)

  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints()
  b.cd:SetReverse(true)
  b.cd:SetDrawEdge(false)

  -- Le compteur passe au-dessus du chrono.
  b.overlay = CreateFrame("Frame", nil, b)
  b.overlay:SetAllPoints()
  b.overlay:SetFrameLevel(b.cd:GetFrameLevel() + 1)
  b.count = b.overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  b.count:SetPoint("BOTTOMRIGHT", 2, -1)

  b:EnableMouse(true)
  if b.SetMouseClickEnabled then b:SetMouseClickEnabled(false) end -- les clics traversent l'icône
  b:SetScript("OnEnter", IconOnEnter)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

-- Trois apparences :
--   "dispel" : debuff que tu peux dissiper → bordure épaisse à la couleur du type, halo qui pulse ;
--   "other"  : debuff que tu ne peux pas dissiper → fine bordure grise, icône un peu assombrie ;
--   "buff"   : buff → fine bordure dorée.
local OTHER_COLOR = { 0.25, 0.25, 0.25 }
local BUFF_COLOR = { 0.85, 0.70, 0.20 }

local function SetStyle(b, kind, dispelName)
  local c
  if kind == "dispel" then
    local t = plain(dispelName)
    c = (t and TYPE_COLORS[t]) or TYPE_COLORS.none
  elseif kind == "buff" then
    c = BUFF_COLOR
  else
    c = OTHER_COLOR
  end
  b.border:SetVertexColor(c[1], c[2], c[3])
  SetBorderSize(b, kind == "dispel" and 2 or 1)

  if kind == "dispel" then
    b.glow:SetVertexColor(c[1], c[2], c[3])
    b.glow:Show()
    if not b.pulse:IsPlaying() then b.pulse:Play() end
  else
    b.pulse:Stop()
    b.glow:Hide()
  end

  local v = kind == "other" and 0.7 or 1
  b.icon:SetVertexColor(v, v, v)
end

local function SetCount(b, unit, a)
  local n = a.applications
  if secret(n) then
    local ok, text = false, nil
    local id = plain(a.auraInstanceID)
    if id and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
      ok, text = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, id, 2, 99)
    end
    if ok then b.count:SetText(text) else b.count:SetText("") end
  else
    b.count:SetText(n and n > 1 and n or "")
  end
end

local function SetTimer(b, unit, a)
  b.cd:SetHideCountdownNumbers(not DB.showTimer)
  local duration, expiration = a.duration, a.expirationTime
  if secret(duration) or secret(expiration) then
    -- Durées protégées : le jeu sait quand même les afficher via un objet « durée ».
    local ok, d = false, nil
    local id = plain(a.auraInstanceID)
    if id and C_UnitAuras and C_UnitAuras.GetAuraDuration and b.cd.SetCooldownFromDurationObject then
      ok, d = pcall(C_UnitAuras.GetAuraDuration, unit, id)
    end
    if not (ok and d and pcall(b.cd.SetCooldownFromDurationObject, b.cd, d)) then b.cd:Clear() end
  elseif duration and duration > 0 and expiration then
    b.cd:SetCooldown(expiration - duration, duration)
  else
    b.cd:Clear()
  end
end

-------------------------------------------------------------------------------
-- Rangées
-------------------------------------------------------------------------------

-- Taille des icônes, nombre au plus et icônes par ligne.
-- Ton cadre est une grille : plus il est large et haut, plus il contient de colonnes et de lignes.
-- Les rangées du groupe reprennent la même grille.
local function RowGeometry(row)
  local s = DB.size
  local cols = math.max(1, math.floor((DB.boxW + GAP) / (s + GAP)))
  local lines = math.max(1, math.floor((DB.boxH + GAP) / (s + GAP)))
  return s, cols * lines, cols, lines
end

local function PlaceIcons(row)
  local s, _, cols, lines = RowGeometry(row)
  if not row.isBox then row:SetSize(cols * (s + GAP) - GAP, lines * (s + GAP) - GAP) end
  for i, b in ipairs(row.icons) do
    local col, line = (i - 1) % cols, math.floor((i - 1) / cols)
    b:SetSize(s, s)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", row, "TOPLEFT", col * (s + GAP), -line * (s + GAP))
  end
end

local function AnchorRow(row)
  local f = row.owner
  row:ClearAllPoints()
  if row.isBox then
    row:SetAllPoints(f)
  elseif DB.position == "droite" then
    row:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
  else
    row:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 2, -2)
  end
end

local function UpdateRow(row)
  local unit = row.unit
  local shown = 0
  local _, max = RowGeometry(row)

  -- En mode /pdb, la souris sert à déplacer ton cadre : pas d'infobulle sur ses icônes.
  local mouse = not (setMode and row.isBox)
  local fake = (testMode or (setMode and row.isBox)) and TEST_AURAS or nil

  if fake then
    -- Faux debuffs : mêmes règles que les vrais (dissipables d'abord, limite, Âme affaiblie toujours).
    local start = GetTime()
    for _, pass in ipairs({ "dispel", "other", "buff" }) do
      local on = (pass == "buff" and DB.showBuffs) or (pass ~= "buff" and DB.showDebuffs)
      for _, a in ipairs(fake) do
        if on and a.kind == pass and (a.always
            or (shown < max and (pass ~= "other" or not DB.onlyDispellable))) then
          shown = shown + 1
          local b = row.icons[shown] or CreateIcon(row)
          row.icons[shown] = b
          b.test, b.unit = a.label, unit
          b.icon:SetTexture(a.icon)
          SetStyle(b, a.kind, a.dispelName)
          b.count:SetText(a.applications > 1 and a.applications or "")
          b.cd:SetHideCountdownNumbers(not DB.showTimer)
          if a.duration > 0 then b.cd:SetCooldown(start - (a.elapsed or 0), a.duration) else b.cd:Clear() end
          b:EnableMouse(mouse)
          b:Show()
        end
      end
    end
  elseif unit and UnitExists(unit) then
    local function Show(index, auraFilter, a, kind)
      shown = shown + 1
      local b = row.icons[shown] or CreateIcon(row)
      row.icons[shown] = b
      b.test, b.unit, b.index, b.filter, b.auraInstanceID = nil, unit, index, auraFilter, plain(a.auraInstanceID)
      b.icon:SetTexture(a.icon)
      SetStyle(b, kind, a.dispelName)
      SetCount(b, unit, a)
      SetTimer(b, unit, a)
      b:EnableMouse(mouse)
      b:Show()
    end
    if DB.showDebuffs then
      -- 1) Debuffs que tu peux dissiper, mis en avant.
      local dispellable = {}
      for _, e in ipairs(AuraList(unit, "HARMFUL|RAID")) do
        if shown >= max then break end
        local a, index = e.a, e.index
        local key = AuraKey(a)
        if key then dispellable[key] = true end
        Show(index, "HARMFUL|RAID", a, "dispel")
      end
      -- 2) Les debuffs de la liste ALWAYS (Âme affaiblie…), trouvés par leur identifiant :
      --    même apparence que les autres non dissipables, mais toujours affichés.
      for _, a in ipairs(FindAlways(unit)) do
        local key = AuraKey(a)
        if not (key and dispellable[key]) then
          Show(nil, "HARMFUL", a, "other")
          if key then dispellable[key] = true end
        end
      end
      -- 3) Tous les autres debuffs, en plus discret.
      for _, e in ipairs(AuraList(unit, "HARMFUL")) do
        local a, index = e.a, e.index
        local key = AuraKey(a)
        if not (key and dispellable[key]) then
          if IsAlways(a) or (not DB.onlyDispellable and shown < max) then
            Show(index, "HARMFUL", a, "other")
          end
        end
      end
    end
    -- 3) Les buffs, après les debuffs, dans la place qui reste.
    if DB.showBuffs then
      for _, e in ipairs(AuraList(unit, "HELPFUL")) do
        if shown >= max then break end
        local a, index = e.a, e.index
        Show(index, "HELPFUL", a, "buff")
      end
    end
  end

  for i = shown + 1, #row.icons do row.icons[i]:Hide() end
  local size, _, cols = RowGeometry(row)
  local key = size .. ":" .. max .. ":" .. cols .. ":" .. #row.icons .. ":" .. tostring(setMode)
  if shown > 0 and row.sized ~= key then
    row.sized = key
    PlaceIcons(row)
  end
end

-- Enfant du cadre suivi : la rangée apparaît et disparaît avec lui.
local function NewRow(frame)
  local row = CreateFrame("Frame", nil, frame)
  row.owner, row.icons = frame, {}
  row:SetFrameStrata("MEDIUM")
  return row
end

local function GetRow(frame)
  local row = rows[frame]
  if not row then
    row = NewRow(frame)
    rows[frame] = row
  end
  return row
end

-------------------------------------------------------------------------------
-- Ton cadre : invisible, accroché à ton cadre joueur, réglable avec /pdb
-------------------------------------------------------------------------------

local function PlaceBox()
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", PlayerFrame, "BOTTOMLEFT", DB.boxX, DB.boxY)
  box:SetSize(DB.boxW, DB.boxH)
end

-- Après un déplacement à la souris, on garde la position par rapport au cadre joueur :
-- si tu bouges ton cadre joueur (mode Édition), tes debuffs le suivent.
local function SaveBox()
  local s, ps = box:GetEffectiveScale(), PlayerFrame:GetEffectiveScale()
  local left, top = box:GetLeft(), box:GetTop()
  local pLeft, pBottom = PlayerFrame:GetLeft(), PlayerFrame:GetBottom()
  if left and top and pLeft and pBottom then
    DB.boxX = (left * s - pLeft * ps) / s
    DB.boxY = (top * s - pBottom * ps) / s
  end
  DB.boxW, DB.boxH = math.floor(box:GetWidth() + 0.5), math.floor(box:GetHeight() + 0.5)
  PlaceBox()
end

local function RefreshBox()
  local row = rows[box]
  if row and row:IsShown() then row.sized = nil; UpdateRow(row) end
end

local function SetBoxEditing(on)
  setMode = on
  box:EnableMouse(on)
  box.bg:SetShown(on)
  box.label:SetShown(on)
  box.grip:SetShown(on)
  RefreshBox()
end

local function CreateBox()
  box = CreateFrame("Frame", "PartyDebuffsPlayerBox", UIParent)
  box:SetFrameStrata("MEDIUM")
  box:SetMovable(true)
  box:SetResizable(true)
  box:SetClampedToScreen(true)
  if box.SetResizeBounds then box:SetResizeBounds(16, 12, 1000, 600)
  elseif box.SetMinResize then box:SetMinResize(16, 12); box:SetMaxResize(1000, 600) end

  -- Visibles seulement pendant /pdb.
  box.bg = box:CreateTexture(nil, "BACKGROUND")
  box.bg:SetAllPoints()
  box.bg:SetColorTexture(0.1, 0.5, 1, 0.3)
  box.label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  box.label:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 2)
  box.label:SetText("Tes auras : glisse pour déplacer, tire le coin pour agrandir la grille.")

  box.grip = CreateFrame("Button", nil, box)
  box.grip:SetSize(16, 16)
  box.grip:SetPoint("BOTTOMRIGHT", 4, -4)
  box.grip:SetFrameLevel(box:GetFrameLevel() + 20)
  box.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  box.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  box.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  box.grip:SetScript("OnMouseDown", function() box:StartSizing("BOTTOMRIGHT") end)
  box.grip:SetScript("OnMouseUp", function() box:StopMovingOrSizing(); SaveBox(); RefreshBox() end)

  box:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then self:StartMoving() end
  end)
  box:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing(); SaveBox() end)
  -- Pendant le redimensionnement, les icônes suivent en direct.
  box:SetScript("OnSizeChanged", function(self, w, h)
    if not setMode then return end
    DB.boxW, DB.boxH = w, h
    RefreshBox()
  end)

  PlaceBox()
  SetBoxEditing(false)
end

-- Les cadres du groupe actuellement utilisés par l'interface Blizzard, avec leur unité.
local function PartyFrames()
  local list = {}
  -- Tes propres debuffs vont dans ton cadre, quel que soit le style des cadres de groupe.
  if DB.showPlayer and box then
    list[#list + 1] = { box, "player" }
  end
  if CompactPartyFrame and CompactPartyFrame:IsShown() then
    for i = 1, 5 do
      local f = _G["CompactPartyFrameMember" .. i]
      local unit = f and plain(f.unit)
      if unit and not (DB.showPlayer and unit == "player") then list[#list + 1] = { f, unit } end
    end
  else
    for i = 1, 4 do
      local f = (PartyFrame and PartyFrame["MemberFrame" .. i]) or _G["PartyMemberFrame" .. i]
      if f then list[#list + 1] = { f, plain(f.unit) or ("party" .. i) } end
    end
  end
  return list
end

local function Layout()
  local used = {}
  for _, entry in ipairs(PartyFrames()) do
    local frame, unit = entry[1], entry[2]
    local row = GetRow(frame)
    row.isBox = frame == box
    row.unit = unit
    row.sized = nil
    AnchorRow(row)
    row:Show()
    used[row] = true
    UpdateRow(row)
  end
  for _, row in pairs(rows) do
    if not used[row] then row.unit = nil; row:Hide() end
  end
end
ns.Layout = Layout

-- Plusieurs événements arrivent souvent d'un coup : on ne refait la mise en place qu'une fois.
local pending = false
local function LayoutSoon()
  if pending then return end
  pending = true
  C_Timer.After(0, function() pending = false; Layout() end)
end

-------------------------------------------------------------------------------
-- Événements
-------------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    PartyDebuffsDB = PartyDebuffsDB or {}
    DB = PartyDebuffsDB
    for k, v in pairs(defaults) do if DB[k] == nil then DB[k] = v end end
    CreateBox()
    self:UnregisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("UNIT_AURA")
    if EventRegistry and EventRegistry.RegisterCallback then
      pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", LayoutSoon, ns)
    end
    if CompactPartyFrame then
      CompactPartyFrame:HookScript("OnShow", LayoutSoon)
      CompactPartyFrame:HookScript("OnHide", LayoutSoon)
    end
    if CompactPartyFrame_Generate then hooksecurefunc("CompactPartyFrame_Generate", LayoutSoon) end
  elseif event == "UNIT_AURA" then
    if secret(arg1) then return end
    for _, row in pairs(rows) do
      if row.unit == arg1 then UpdateRow(row) end
    end
  else
    LayoutSoon()
  end
end)

-------------------------------------------------------------------------------
-- /pdb : fenêtre de réglages
-------------------------------------------------------------------------------

local gui
local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local VERSION = (GetMeta and GetMeta(ADDON, "Version")) or "?"

local function RefreshAll()
  Layout()
end

local function AddCheck(parent, y, text, get, set)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  c:SetPoint("TOPLEFT", 10, y)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("LEFT", c, "RIGHT", 4, 0)
  label:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
  label:SetJustifyH("LEFT")
  label:SetWordWrap(false)
  label:SetText(text)
  c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); RefreshAll() end)
  c.Sync = function(self) self:SetChecked(get()) end
  return c
end

local function AddSlider(parent, y, text, min, max, get, set)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("TOPLEFT", 14, y)
  local s = CreateFrame("Slider", nil, parent)
  s:SetOrientation("HORIZONTAL")
  s:SetHeight(16)
  s:SetPoint("TOPLEFT", 40, y - 20)
  s:SetPoint("RIGHT", parent, "RIGHT", -40, 0)
  local low = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  low:SetPoint("RIGHT", s, "LEFT", -6, 0)
  low:SetText(min)
  local high = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  high:SetPoint("LEFT", s, "RIGHT", 6, 0)
  high:SetText(max)
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  track:SetHeight(6)
  track:SetColorTexture(0.25, 0.25, 0.25, 1)
  s:SetMinMaxValues(min, max)
  s:SetValueStep(1)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  local function ShowValue(v) label:SetText(text .. " : |cffffffff" .. v .. "|r") end
  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v + 0.5)
    ShowValue(v)
    if self.syncing or v == get() then return end
    set(v)
    RefreshAll()
  end)
  s.Sync = function(self)
    self.syncing = true
    self:SetValue(get())
    self.syncing = false
    ShowValue(get())
  end
  return s
end

local function AddButton(parent, x, y, w, text, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetPoint("TOPLEFT", x, y)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function SyncGui()
  for _, w in ipairs(gui.widgets) do w:Sync() end
  gui.testButton:SetText(testMode and "Arrêter le test" or "Test")
end

-- Même style que les fenêtres de QuestChums et Red Flag : cadre Blizzard avec titre, encarts.
local GUI_W = 460

local function Section(parent, y, height, title)
  local inset = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
  inset:SetPoint("TOPLEFT", 14, y)
  inset:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
  inset:SetHeight(height)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 4, 3)
  label:SetText(title)
  return inset
end

local function CreateGui()
  gui = CreateFrame("Frame", "PartyDebuffsSettings", UIParent, "BasicFrameTemplateWithInset")
  gui:SetWidth(GUI_W)
  gui:SetPoint("CENTER", 200, 0)
  gui:SetFrameStrata("DIALOG")
  gui:SetMovable(true)
  gui:SetClampedToScreen(true)
  gui:EnableMouse(true)
  gui:RegisterForDrag("LeftButton")
  gui:SetScript("OnDragStart", gui.StartMoving)
  gui:SetScript("OnDragStop", gui.StopMovingOrSizing)
  gui.TitleText:SetText("PartyDebuffs — Réglages  |cff999999v" .. VERSION .. "|r")
  -- Fermer la fenêtre (croix, Échap ou bouton) termine le réglage de ton cadre.
  gui:SetScript("OnHide", function() SetBoxEditing(false) end)
  tinsert(UISpecialFrames, "PartyDebuffsSettings")

  local w = {}

  -- Affichage
  local checks = {
    { "Afficher les debuffs", "showDebuffs" },
    { "Afficher les buffs", "showBuffs" },
    { "Seulement les debuffs que tu peux dissiper", "onlyDispellable" },
    { "Afficher le temps restant sur les icônes", "showTimer" },
    { "Afficher tes propres auras (cadre bleu)", "showPlayer" },
    { "Rangées à droite des cadres du groupe (sinon dessous)", "position" },
  }
  local y = -54
  local display = Section(gui, y, #checks * 26 + 12, "Affichage")
  for i, c in ipairs(checks) do
    local text, key = c[1], c[2]
    local get, set
    if key == "position" then
      get = function() return DB.position == "droite" end
      set = function(v) DB.position = v and "droite" or "dessous" end
    else
      get = function() return DB[key] end
      set = function(v) DB[key] = v end
    end
    w[#w + 1] = AddCheck(display, -6 - (i - 1) * 26, text, get, set)
  end
  y = y - display:GetHeight() - 30

  -- Taille
  local size = Section(gui, y, 60, "Taille")
  w[#w + 1] = AddSlider(size, -10, "Taille des icônes", 12, 48,
    function() return DB.size end, function(v) DB.size = v end)
  y = y - size:GetHeight() - 10

  local hint = gui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 18, y)
  hint:SetPoint("RIGHT", gui, "RIGHT", -18, 0)
  hint:SetJustifyH("LEFT")
  hint:SetSpacing(2)
  hint:SetText("Le cadre bleu contient tes auras. Glisse-le pour le déplacer, et tire son coin en bas "
               .. "à droite pour agrandir la grille : plus de colonnes et de lignes. Les membres du groupe "
               .. "reprennent la même grille.")
  y = y - 40

  local bw = (GUI_W - 28 - 2 * 8) / 3
  gui.testButton = AddButton(gui, 14, y, bw, "Test", function()
    testMode = not testMode
    SyncGui()
    RefreshAll()
  end)
  AddButton(gui, 14 + (bw + 8), y, bw, "Réinitialiser", function()
    for k, v in pairs(defaults) do DB[k] = v end
    PlaceBox()
    SyncGui()
    RefreshAll()
  end)
  AddButton(gui, 14 + 2 * (bw + 8), y, bw, "Terminer", function() gui:Hide() end)

  gui.widgets = w
  gui:SetHeight(-y + 22 + 16)
  gui:Hide()
end

local function ToggleGui()
  if not gui then CreateGui() end
  if gui:IsShown() then
    gui:Hide()
    Print("réglages enregistrés.")
  else
    SyncGui()
    gui:Show()
    SetBoxEditing(true)
    Layout()
  end
end

-------------------------------------------------------------------------------
-- Commande /pdb
-------------------------------------------------------------------------------

local function Help()
  Print("commandes :")
  Print("  /pdb taille <12-48>  (actuellement " .. DB.size .. ")")
  Print("  /pdb position dessous|droite  (actuellement " .. DB.position .. ")")
  Print("  /pdb dissipables : seulement ceux que tu peux dissiper (" .. (DB.onlyDispellable and "oui" or "non") .. ")")
  Print("  /pdb chrono : affiche le temps restant (" .. (DB.showTimer and "oui" or "non") .. ")")
  Print("  /pdb moi : affiche tes propres debuffs (" .. (DB.showPlayer and "oui" or "non") .. ")")
  Print("  /pdb : ouvre la fenêtre de réglages (tous les réglages, et la grille de tes auras à la souris)")
  Print("  /pdb test : affiche de faux debuffs pour voir le rendu")
  Print("  /pdb debug : liste dans le chat les debuffs lus par l'addon")
  Print("  /pdb reset : réglages par défaut")
  Print("  /pdb aide : cette liste")
end

SLASH_PARTYDEBUFFS1 = "/pdb"
SLASH_PARTYDEBUFFS2 = "/partydebuffs"
SlashCmdList.PARTYDEBUFFS = function(msg)
  local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  local n = tonumber(arg)
  if cmd == "taille" and n then
    DB.size = math.max(12, math.min(48, math.floor(n)))
    Print("taille des icônes : " .. DB.size)
  elseif cmd == "position" and (arg == "dessous" or arg == "droite") then
    DB.position = arg
    Print("position : " .. arg)
  elseif cmd == "dissipables" then
    DB.onlyDispellable = not DB.onlyDispellable
    Print(DB.onlyDispellable and "seulement les debuffs que tu peux dissiper." or "tous les debuffs.")
  elseif cmd == "chrono" then
    DB.showTimer = not DB.showTimer
    Print(DB.showTimer and "chrono affiché." or "chrono masqué.")
  elseif cmd == "moi" then
    DB.showPlayer = not DB.showPlayer
    Print(DB.showPlayer and "tes debuffs sont affichés." or "tes debuffs ne sont plus affichés.")
    if not DB.showPlayer and setMode then SetBoxEditing(false) end
  elseif cmd == "" or cmd == "set" then
    ToggleGui()
    return
  elseif cmd == "debug" then
    ns:Debug()
    return
  elseif cmd == "test" then
    testMode = not testMode
    Print(testMode and "mode test activé (retape /pdb test pour l'arrêter). Les rangées n'apparaissent que si les cadres du groupe sont affichés."
                    or "mode test désactivé.")
  elseif cmd == "reset" then
    for k, v in pairs(defaults) do DB[k] = v end
    PlaceBox()
    Print("réglages par défaut remis.")
  else
    Help()
    return
  end
  RefreshAll()
  if gui and gui:IsShown() then SyncGui() end
end

-------------------------------------------------------------------------------
-- /pdb debug : ce que l'addon voit, pour comprendre un debuff qui n'apparaît pas
-------------------------------------------------------------------------------

local function Show(v)
  if secret(v) then return "<protégé>" end
  if v == nil then return "nil" end
  return tostring(v)
end

function ns:Debug()
  local _, _, _, build = GetBuildInfo()
  Print(("version du jeu %s, combat=%s, groupe=%s, raid=%s, cadres style raid=%s"):format(
    Show(build), Show(InCombatLockdown()), Show(IsInGroup()), Show(IsInRaid()),
    Show(CompactPartyFrame and CompactPartyFrame:IsShown() or false)))
  Print("API : C_UnitAuras.GetAuraDataByIndex=" .. Show(C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and true or false)
        .. ", UnitDebuff=" .. Show(UnitDebuff and true or false))
  for id in pairs(ALWAYS) do Print(("toujours affiché : sort %d = %s"):format(id, Show(SpellName(id)))) end

  local units = { "player", "party1", "party2", "party3", "party4" }
  for _, unit in ipairs(units) do
    if UnitExists(unit) then
      local row
      for _, r in pairs(rows) do if r.unit == unit then row = r end end
      Print(("%s (%s) : rangée=%s, visible=%s, icônes=%d"):format(unit, Show(UnitName(unit)),
        row and (row.owner:GetName() or "?") or "aucune", Show(row and row:IsVisible() or false),
        row and #row.icons or 0))
      local found = FindAlways(unit)
      Print(("    recherche par identifiant (Âme affaiblie…) : %d trouvé(s)%s"):format(#found,
        found[1] and (", aura " .. Show(found[1].auraInstanceID)) or ""))
      local list = AuraList(unit, "HARMFUL")
      if #list == 0 then Print("    aucun debuff lu (ou lecture refusée par le jeu)") end
      for i, e in ipairs(list) do
        local a = e.a
        Print(("    %d. %s, sort %s, type %s, toujours=%s%s"):format(i, Show(a.name), Show(a.spellId),
          Show(a.dispelName), Show(IsAlways(a)), e.index and "" or " (lu par identifiant)"))
      end
    end
  end
end
