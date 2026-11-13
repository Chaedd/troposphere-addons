-- PartyDebuffs : une rangée d'icônes de debuffs sous chaque cadre de membre du groupe.
local ADDON, ns = ...
PartyDebuffs = ns

local defaults = {
  size = 20,             -- taille d'une icône, en pixels
  max = 8,               -- icônes affichées par membre, au plus
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
local setMode = false    -- /pdb set : cadre de tes debuffs déplaçable et redimensionnable
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
local function secret(v) return issecretvalue and issecretvalue(v) or false end

-------------------------------------------------------------------------------
-- Lecture des debuffs
-------------------------------------------------------------------------------

-- Lit un debuff (filtre "HARMFUL…") ou un buff (filtre "HELPFUL…").
local function GetDebuff(unit, index, filter)
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    return C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
  end
  local read = UnitAura or (filter:find("HELPFUL") and UnitBuff or UnitDebuff)
  if read then
    local name, icon, count, dispelType, duration, expirationTime, _, _, _, spellId = read(unit, index, filter)
    if name then
      return { name = name, icon = icon, applications = count, dispelName = dispelType,
               duration = duration, expirationTime = expirationTime, spellId = spellId }
    end
  end
end

-- Debuffs toujours affichés, même avec /pdb dissipables et au-delà de /pdb max.
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
  local id = a.spellId
  if id and not secret(id) then return ALWAYS[id] or false end
  local name = a.name
  if name and not secret(name) then return ALWAYS_NAMES[name] or false end
  return false
end

-- Identifie un debuff pour ne pas l'afficher deux fois (il ressort dans les deux listes : dissipables et tous).
local function AuraKey(a)
  local id = a.auraInstanceID
  if id and not secret(id) then return id end
  local name, expiration = a.name, a.expirationTime
  if name and expiration and not secret(name) and not secret(expiration) then
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
  else
    GameTooltip:SetUnitDebuff(self.unit, self.index, self.filter)
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
    c = (dispelName and not secret(dispelName) and TYPE_COLORS[dispelName]) or TYPE_COLORS.none
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
    if a.auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
      ok, text = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, a.auraInstanceID, 2, 99)
    end
    b.count:SetText(ok and text or "")
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
    if a.auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraDuration and b.cd.SetCooldownFromDurationObject then
      ok, d = pcall(C_UnitAuras.GetAuraDuration, unit, a.auraInstanceID)
    end
    if ok and d then b.cd:SetCooldownFromDurationObject(d) else b.cd:Clear() end
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
local function RowGeometry(row)
  local s = DB.size
  if row.isBox then
    local cols = math.max(1, math.floor((DB.boxW + GAP) / (s + GAP)))
    local lines = math.max(1, math.floor((DB.boxH + GAP) / (s + GAP)))
    return s, cols * lines, cols
  end
  return s, DB.max, DB.max
end

local function PlaceIcons(row)
  local s, max, cols = RowGeometry(row)
  if not row.isBox then row:SetSize(max * (s + GAP), s) end
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
    row:SetPoint("LEFT", f, "RIGHT", 4, 0)
  else
    row:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 2, -2)
  end
end

local function UpdateRow(row)
  local unit = row.unit
  local shown = 0
  local _, max = RowGeometry(row)

  -- En mode /pdb set, la souris sert à déplacer ton cadre : pas d'infobulle sur ses icônes.
  local mouse = not (setMode and row.isBox)
  local fake = row.fakeAuras or ((testMode or (setMode and row.isBox)) and TEST_AURAS) or nil

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
      b.test, b.unit, b.index, b.filter, b.auraInstanceID = nil, unit, index, auraFilter, a.auraInstanceID
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
      for index = 1, 40 do
        if shown >= max then break end
        local a = GetDebuff(unit, index, "HARMFUL|RAID")
        if not a then break end
        local key = AuraKey(a)
        if key then dispellable[key] = true end
        Show(index, "HARMFUL|RAID", a, "dispel")
      end
      -- 2) Tous les autres debuffs, en plus discret. Ceux de la liste ALWAYS (Âme affaiblie…)
      --    ont la même apparence, mais s'affichent même au-delà de la limite ou avec /pdb dissipables.
      for index = 1, 40 do
        local a = GetDebuff(unit, index, "HARMFUL")
        if not a then break end
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
      for index = 1, 40 do
        if shown >= max then break end
        local a = GetDebuff(unit, index, "HELPFUL")
        if not a then break end
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
-- Ton cadre : invisible, accroché à ton cadre joueur, réglable avec /pdb set
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

  -- Visibles seulement pendant /pdb set.
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
      if f and f.unit and not (DB.showPlayer and f.unit == "player") then list[#list + 1] = { f, f.unit } end
    end
  else
    for i = 1, 4 do
      local f = (PartyFrame and PartyFrame["MemberFrame" .. i]) or _G["PartyMemberFrame" .. i]
      if f then list[#list + 1] = { f, f.unit or ("party" .. i) } end
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
-- /pdb testraid : faux raid de 20 joueurs, avec plus ou moins de debuffs chacun
-------------------------------------------------------------------------------

local fakeRaid
local RAID_GROUPS, GROUP_SIZE = 4, 5
local FAKE_W, FAKE_H = 100, 28

local FAKE_CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "HUNTER", "WARLOCK", "PALADIN", "SHAMAN" }
local FAKE_NAMES = {
  "Brakmor", "Lumina", "Fizzle", "Ombrelame", "Feuillevent", "Tirelune", "Nyxara", "Aldric", "Tonnerrebrume", "Gorrak",
  "Séraphine", "Pyrus", "Vexa", "Sylvain", "Arcos", "Morvenna", "Talbrecht", "Ondine", "Krag", "Elowen",
}
-- Debuffs de test par joueur : de 0 à bien plus que la limite.
local FAKE_COUNTS = { 0, 1, 2, 3, 0, 5, 8, 1, 12, 0, 2, 16, 4, 0, 25, 1, 6, 0, 3, 20 }

local FAKE_POOL = {
  { kind = "dispel", dispelName = "Magic",   label = "Magie, dissipable",          icon = "Interface\\Icons\\Spell_Frost_FrostNova" },
  { kind = "other",  dispelName = "Curse",   label = "Malédiction",                icon = "Interface\\Icons\\Spell_Shadow_CurseOfSargeras" },
  { kind = "other",  label = "non dissipable",                                    icon = "Interface\\Icons\\Ability_Gouge" },
  { kind = "dispel", dispelName = "Poison",  label = "Poison, dissipable",         icon = "Interface\\Icons\\Spell_Nature_CorrosiveBreath" },
  { kind = "other",  dispelName = "Disease", label = "Maladie",                    icon = "Interface\\Icons\\Spell_Shadow_AbominationExplosion" },
  { kind = "other",  label = "non dissipable",                                    icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain" },
  { kind = "dispel", dispelName = "Magic",   label = "Magie, dissipable",          icon = "Interface\\Icons\\Spell_Nature_Slow" },
  { kind = "other",  label = "non dissipable",                                    icon = "Interface\\Icons\\Spell_Fire_Immolation" },
}
local FAKE_WEAKENED_SOUL = { kind = "other", always = true, label = "Âme affaiblie, toujours affichée",
                             icon = "Interface\\Icons\\Spell_Holy_AshesToAshes", applications = 1, duration = 15 }

local FAKE_BUFFS = {
  { kind = "buff", label = "buff", icon = "Interface\\Icons\\Spell_Holy_WordFortitude",     applications = 1, duration = 0 },
  { kind = "buff", label = "buff", icon = "Interface\\Icons\\Spell_Nature_Regeneration",    applications = 1, duration = 0 },
  { kind = "buff", label = "buff", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",     applications = 1, duration = 0 },
  { kind = "buff", label = "buff", icon = "Interface\\Icons\\Spell_Nature_Rejuvenation",    applications = 1, duration = 12, elapsed = 3 },
  { kind = "buff", label = "buff", icon = "Interface\\Icons\\Spell_Holy_PowerWordShield",   applications = 1, duration = 30, elapsed = 10 },
}

local function FakeAuras(member, count)
  local list = {}
  for j = 1, count do
    local p = FAKE_POOL[(member + j) % #FAKE_POOL + 1]
    list[j] = { kind = p.kind, dispelName = p.dispelName, label = p.label, icon = p.icon,
                applications = (j % 5 == 0) and 3 or 1,
                duration = (j % 4 == 0) and 0 or (10 + (member * 7 + j * 3) % 50),
                elapsed = (member + j) % 9 }
  end
  -- Un joueur sur quatre a aussi Âme affaiblie, rangée en dernier : elle doit quand même s'afficher.
  if member % 4 == 0 then list[#list + 1] = FAKE_WEAKENED_SOUL end
  -- Quelques buffs, visibles si « Afficher les buffs » est coché.
  for j = 1, member % 4 + 1 do
    list[#list + 1] = FAKE_BUFFS[(member + j) % #FAKE_BUFFS + 1]
  end
  return list
end

local function LayoutFakeRaid()
  local s, max = DB.size, DB.max
  local rowW = max * (s + GAP)
  local colW, stepY
  if DB.position == "droite" then
    colW, stepY = FAKE_W + 4 + rowW + 12, FAKE_H + 8
  else
    colW, stepY = math.max(FAKE_W, rowW) + 12, FAKE_H + 2 + s + 10
  end
  fakeRaid:SetSize(colW * RAID_GROUPS + 20, stepY * GROUP_SIZE + 50)
  for i, m in ipairs(fakeRaid.members) do
    local g, k = math.floor((i - 1) / GROUP_SIZE), (i - 1) % GROUP_SIZE
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", fakeRaid, "TOPLEFT", 10 + g * colW, -36 - k * stepY)
    m.row.sized = nil
    AnchorRow(m.row)
    UpdateRow(m.row)
  end
end

local function CreateFakeRaid()
  fakeRaid = CreateFrame("Frame", "PartyDebuffsTestRaid", UIParent)
  fakeRaid:SetFrameStrata("DIALOG")
  fakeRaid:SetPoint("CENTER")
  fakeRaid:SetMovable(true)
  fakeRaid:SetClampedToScreen(true)
  fakeRaid:EnableMouse(true)
  fakeRaid:RegisterForDrag("LeftButton")
  fakeRaid:SetScript("OnDragStart", fakeRaid.StartMoving)
  fakeRaid:SetScript("OnDragStop", fakeRaid.StopMovingOrSizing)

  local bg = fakeRaid:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.75)
  local title = fakeRaid:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -10)
  title:SetText("PartyDebuffs : faux raid (glisse pour déplacer, /pdb testraid pour fermer)")
  local close = CreateFrame("Button", nil, fakeRaid, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function() fakeRaid:Hide() end)

  fakeRaid.members = {}
  for i = 1, RAID_GROUPS * GROUP_SIZE do
    local m = CreateFrame("Frame", nil, fakeRaid)
    m:SetSize(FAKE_W, FAKE_H)
    local mbg = m:CreateTexture(nil, "BACKGROUND")
    mbg:SetAllPoints()
    mbg:SetColorTexture(0.15, 0.15, 0.15, 1)
    local class = FAKE_CLASSES[(i - 1) % #FAKE_CLASSES + 1]
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] or { r = 0.5, g = 0.5, b = 0.5 }
    local bar = m:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMLEFT", 1, 1)
    bar:SetWidth((FAKE_W - 2) * (0.35 + ((i * 37) % 65) / 100))
    bar:SetColorTexture(c.r, c.g, c.b, 1)
    local name = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", 4, 0)
    name:SetText(FAKE_NAMES[i] .. " |cffaaaaaa(" .. FAKE_COUNTS[i] .. ")|r")

    m.row = NewRow(m)
    m.row:SetFrameStrata("DIALOG")
    m.row.fakeAuras = FakeAuras(i, FAKE_COUNTS[i])
    m.row:Show()
    fakeRaid.members[i] = m
  end
  fakeRaid:Hide()
end

local function ToggleFakeRaid()
  if not fakeRaid then CreateFakeRaid() end
  if fakeRaid:IsShown() then
    fakeRaid:Hide()
    Print("faux raid fermé.")
  else
    fakeRaid:Show()
    LayoutFakeRaid()
    Print("faux raid affiché. Entre parenthèses : le nombre de debuffs de chaque joueur. "
          .. "Change /pdb max, taille, position ou dissipables pour voir comment ça réagit.")
  end
end

-------------------------------------------------------------------------------
-- /pdb set : fenêtre de réglages
-------------------------------------------------------------------------------

local gui
local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local VERSION = (GetMeta and GetMeta(ADDON, "Version")) or "?"

local function RefreshAll()
  Layout()
  if fakeRaid and fakeRaid:IsShown() then LayoutFakeRaid() end
end

local function AddCheck(parent, y, text, get, set)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  c:SetPoint("TOPLEFT", 14, y)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("LEFT", c, "RIGHT", 4, 0)
  label:SetText(text)
  c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); RefreshAll() end)
  c.Sync = function(self) self:SetChecked(get()) end
  return c
end

local function AddSlider(parent, y, text, min, max, get, set)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("TOPLEFT", 18, y)
  local s = CreateFrame("Slider", nil, parent)
  s:SetOrientation("HORIZONTAL")
  s:SetSize(260, 16)
  s:SetPoint("TOPLEFT", 18, y - 18)
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

local function CreateGui()
  gui = CreateFrame("Frame", "PartyDebuffsSettings", UIParent)
  gui:SetSize(310, 470)
  gui:SetPoint("CENTER", 200, 0)
  gui:SetFrameStrata("DIALOG")
  gui:SetMovable(true)
  gui:SetClampedToScreen(true)
  gui:EnableMouse(true)
  gui:RegisterForDrag("LeftButton")
  gui:SetScript("OnDragStart", gui.StartMoving)
  gui:SetScript("OnDragStop", gui.StopMovingOrSizing)
  -- Fermer la fenêtre (croix, Échap ou bouton) termine le réglage de ton cadre.
  gui:SetScript("OnHide", function() SetBoxEditing(false) end)
  tinsert(UISpecialFrames, "PartyDebuffsSettings")

  local bg = gui:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.05, 0.08, 0.92)
  local title = gui:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("PartyDebuffs")
  local version = gui:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  version:SetPoint("LEFT", title, "RIGHT", 6, -1)
  version:SetText("v" .. VERSION)
  local close = CreateFrame("Button", nil, gui, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  local w, y = {}, -40
  local function check(text, key)
    w[#w + 1] = AddCheck(gui, y, text, function() return DB[key] end, function(v) DB[key] = v end)
    y = y - 26
  end
  check("Afficher les debuffs", "showDebuffs")
  check("Afficher les buffs", "showBuffs")
  check("Seulement les debuffs que tu peux dissiper", "onlyDispellable")
  check("Afficher le temps restant", "showTimer")
  check("Afficher tes propres auras (cadre bleu)", "showPlayer")
  w[#w + 1] = AddCheck(gui, y, "Rangées à droite des cadres (sinon dessous)",
    function() return DB.position == "droite" end,
    function(v) DB.position = v and "droite" or "dessous" end)
  y = y - 40

  w[#w + 1] = AddSlider(gui, y, "Taille des icônes", 12, 48,
    function() return DB.size end, function(v) DB.size = v end)
  y = y - 50
  w[#w + 1] = AddSlider(gui, y, "Icônes par membre du groupe", 1, 16,
    function() return DB.max end, function(v) DB.max = v end)
  y = y - 50

  local hint = gui:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hint:SetPoint("TOPLEFT", 18, y)
  hint:SetWidth(275)
  hint:SetJustifyH("LEFT")
  hint:SetText("Le cadre bleu contient tes auras : glisse-le pour le déplacer, tire son coin en bas à droite "
               .. "pour agrandir la grille (plus de colonnes et de lignes).")
  y = y - 52

  gui.testButton = AddButton(gui, 14, y, 92, "Test", function()
    testMode = not testMode
    SyncGui()
    RefreshAll()
  end)
  AddButton(gui, 110, y, 92, "Faux raid", function() ToggleFakeRaid() end)
  AddButton(gui, 206, y, 92, "Réinitialiser", function()
    for k, v in pairs(defaults) do DB[k] = v end
    PlaceBox()
    SyncGui()
    RefreshAll()
  end)
  y = y - 32
  AddButton(gui, 110, y, 92, "Terminer", function() gui:Hide() end)

  gui.widgets = w
  gui:SetHeight(-y + 36)
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
  Print("  /pdb max <1-16>  (actuellement " .. DB.max .. ")")
  Print("  /pdb position dessous|droite  (actuellement " .. DB.position .. ")")
  Print("  /pdb dissipables : seulement ceux que tu peux dissiper (" .. (DB.onlyDispellable and "oui" or "non") .. ")")
  Print("  /pdb chrono : affiche le temps restant (" .. (DB.showTimer and "oui" or "non") .. ")")
  Print("  /pdb moi : affiche tes propres debuffs (" .. (DB.showPlayer and "oui" or "non") .. ")")
  Print("  /pdb set : ouvre la fenêtre de réglages (tous les réglages, et le cadre de tes auras à la souris)")
  Print("  /pdb test : affiche de faux debuffs pour voir le rendu")
  Print("  /pdb testraid : affiche un faux raid de 20 joueurs, avec plus ou moins de debuffs")
  Print("  /pdb debug : liste dans le chat les debuffs lus par l'addon")
  Print("  /pdb reset : réglages par défaut")
end

SLASH_PARTYDEBUFFS1 = "/pdb"
SLASH_PARTYDEBUFFS2 = "/partydebuffs"
SlashCmdList.PARTYDEBUFFS = function(msg)
  local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  local n = tonumber(arg)
  if cmd == "taille" and n then
    DB.size = math.max(12, math.min(48, math.floor(n)))
    Print("taille des icônes : " .. DB.size)
  elseif cmd == "max" and n then
    DB.max = math.max(1, math.min(16, math.floor(n)))
    Print("icônes par membre : " .. DB.max)
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
  elseif cmd == "set" then
    ToggleGui()
    return
  elseif cmd == "testraid" then
    ToggleFakeRaid()
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
  if v == nil then return "nil" end
  if secret(v) then return "<protégé>" end
  return tostring(v)
end

function ns:Debug()
  local _, _, _, build = GetBuildInfo()
  Print(("version du jeu %s, groupe=%s, raid=%s, cadres style raid=%s"):format(
    Show(build), Show(IsInGroup()), Show(IsInRaid()),
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
      for index = 1, 40 do
        local a = GetDebuff(unit, index, "HARMFUL")
        if not a then
          if index == 1 then Print("    aucun debuff lu") end
          break
        end
        Print(("    %d. %s, sort %s, type %s, toujours=%s"):format(index, Show(a.name), Show(a.spellId),
          Show(a.dispelName), Show(IsAlways(a))))
      end
    end
  end
end
