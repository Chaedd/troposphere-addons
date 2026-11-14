-- GuildCraft : lecture de mes métiers.
-- Les recettes ne se lisent que fenêtre de métier ouverte. On garde leur rangement : la
-- catégorie et l'ordre de la fenêtre, pour l'afficher pareil. On note aussi les composants.
-- Sur Classic, la fenêtre peut être filtrée (catégories repliées, « composants
-- disponibles ») : on fusionne alors ce qu'on voit avec ce qu'on savait déjà, sans rien
-- retirer. Une recette ne s'oublie pas, sauf en abandonnant le métier : on repart de zéro
-- si le rang baisse ou si le métier disparaît.
local _, ns = ...
local M = ns.Model

local function linkItemID(link)
  return type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
end

local function itemToken(link)
  local id = linkItemID(link)
  return id and M.Token("i", id)
end

local function spellToken(link)
  if type(link) ~= "string" then return nil end
  local id = tonumber(link:match("|Henchant:(%d+)") or link:match("|Hspell:(%d+)") or link:match("|Htrade:[^:]*:(%d+)"))
  return id and M.Token("s", id)
end

-- Enregistre ce que je sais d'un métier ; complete = la liste lue est entière.
function ns:UpdateOwn(p, rank, max, seq, complete)
  local own = self.char.profs[p]
  if own and not complete and not (rank and own.rank and rank < own.rank) then
    local cats, lists = M.MergeLayouts({ seq, own.seq or {} })
    seq = M.FlattenLayout(cats, lists, M.MAX_RECIPES)
  end
  local hash = M.Hash(seq)
  rank, max = rank or (own and own.rank) or 0, max or (own and own.max) or 0
  if own and own.hash == hash and own.rank == rank and own.max == max then return end
  self.char.profs[p] = { rank = rank, max = max, seq = seq, n = #seq, hash = hash }
  self:MirrorOwn()
  self:Announce()
end

-- Composants lus dans la fenêtre ; nil si l'un d'eux n'est pas encore connu du jeu.
local function readReagents(count, info, link)
  local list = {}
  for j = 1, count or 0 do
    local _, _, n = info(j)
    local id = linkItemID(link(j))
    if not id or not n then return nil end
    list[#list + 1] = { id = id, n = n }
  end
  return list
end

-- Classic : fenêtre de métier (TradeSkill).
local function scanTradeSkill()
  if not GetTradeSkillLine or not GetNumTradeSkills then return end
  if IsTradeSkillLinked and IsTradeSkillLinked() then return end
  local name, rank, max = GetTradeSkillLine()
  local p = ns:ProfessionByName(name)
  if not p then return end
  local seq, cat = {}, ""
  for i = 1, GetNumTradeSkills() do
    local rname, kind = GetTradeSkillInfo(i)
    if kind == "header" or kind == "subheader" then
      cat = rname or ""
    elseif rname then
      local t = itemToken(GetTradeSkillItemLink and GetTradeSkillItemLink(i))
        or spellToken(GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i))
      if t then
        seq[#seq + 1] = { t = t, c = cat }
        if GetTradeSkillNumReagents and GetTradeSkillReagentItemLink then
          ns:StoreReagents(t, readReagents(GetTradeSkillNumReagents(i),
            function(j) return GetTradeSkillReagentInfo(i, j) end,
            function(j) return GetTradeSkillReagentItemLink(i, j) end))
        end
      end
    end
  end
  ns:UpdateOwn(p, rank, max, seq, false)
end

-- Classic : enchantement passe par l'ancienne fenêtre « Craft ».
local function scanCraft()
  if not GetCraftDisplaySkillLine or not GetNumCrafts then return end
  local name, rank, max = GetCraftDisplaySkillLine()
  local p = ns:ProfessionByName(name)
  if not p then return end
  local seq, cat = {}, ""
  for i = 1, GetNumCrafts() do
    local cname, _, kind = GetCraftInfo(i)
    if kind == "header" then
      cat = cname or ""
    elseif cname then
      local link = GetCraftItemLink and GetCraftItemLink(i)
      local t = spellToken(link) or itemToken(link)
        or spellToken(GetCraftRecipeLink and GetCraftRecipeLink(i))
      if t then
        seq[#seq + 1] = { t = t, c = cat }
        if GetCraftNumReagents and GetCraftReagentItemLink then
          ns:StoreReagents(t, readReagents(GetCraftNumReagents(i),
            function(j) return GetCraftReagentInfo(i, j) end,
            function(j) return GetCraftReagentItemLink(i, j) end))
        end
      end
    end
  end
  ns:UpdateOwn(p, rank, max, seq, false)
end

-- Retail : composants lus dans le schéma de la recette, sans fenêtre ouverte.
function ns:RetailReagents(recipeID)
  local T = C_TradeSkillUI
  if not (T and T.GetRecipeSchematic) then return nil end
  local ok, schematic = pcall(T.GetRecipeSchematic, recipeID, false)
  if not ok or type(schematic) ~= "table" then return nil end
  local list = {}
  for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    local first = slot.reagents and slot.reagents[1]
    if first and first.itemID and (basic == nil or slot.reagentType == basic) then
      list[#list + 1] = { id = first.itemID, n = slot.quantityRequired or 1 }
    end
  end
  return list
end

-- Objet fabriqué par une recette (API moderne), ou nil pour un enchantement.
local function outputItem(recipeID, info)
  local T = C_TradeSkillUI
  if T.GetRecipeOutputItemData then
    local ok, data = pcall(T.GetRecipeOutputItemData, recipeID)
    if ok and type(data) == "table" then
      local id = data.itemID or linkItemID(data.hyperlink)
      if id then return id end
    end
  end
  if T.GetRecipeItemLink then
    local ok, link = pcall(T.GetRecipeItemLink, recipeID)
    local id = ok and linkItemID(link)
    if id then return id end
  end
  return linkItemID(info and info.hyperlink)
end

-- Retail : la liste des recettes est complète, même avec un filtre.
local function scanRetail()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs and T.GetBaseProfessionInfo and T.GetRecipeInfo) then return end
  if T.IsTradeSkillReady and not T.IsTradeSkillReady() then return end
  if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
    or (T.IsNPCCrafting and T.IsNPCCrafting()) or (T.IsRuneforging and T.IsRuneforging()) then return end
  local base = T.GetBaseProfessionInfo()
  local p = base and base.professionID
  if not p or not ns.ProfessionsByID[p] then return end
  local child = T.GetChildProfessionInfo and T.GetChildProfessionInfo()
  local rank = (child and child.skillLevel) or base.skillLevel
  local max = (child and child.maxSkillLevel) or base.maxSkillLevel

  local cats = {}
  local function category(id)
    if not id then return { name = "", order = 0 } end
    if cats[id] == nil then
      local info = T.GetCategoryInfo and T.GetCategoryInfo(id)
      cats[id] = { name = info and info.name or "", order = info and info.uiOrder or 0 }
    end
    return cats[id]
  end
  local list = {}
  for index, id in ipairs(T.GetAllRecipeIDs() or {}) do
    local r = T.GetRecipeInfo(id)
    if r and r.learned and not r.isRecraft and not r.isDummyRecipe then
      -- Une recette qui fabrique un objet est rangée sous cet objet : son icône, sa qualité
      -- et son infobulle sont les bonnes (le sort de fabrication a une icône générique).
      local t = M.Token("i", outputItem(id, r)) or M.Token("s", id)
      if t then
        local reagents = ns:RetailReagents(id)
        if reagents and #reagents > 0 then ns:StoreReagents(t, reagents) end
        local c = category(r.categoryID)
        list[#list + 1] = { t = t, c = c.name, order = c.order, index = index }
      end
    end
  end
  table.sort(list, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.index < b.index
  end)
  local seq = {}
  for _, e in ipairs(list) do seq[#seq + 1] = { t = e.t, c = e.c } end
  ns:UpdateOwn(p, rank, max, seq, true)
end

-- Version 1.1.1 et avant : mes recettes étaient rangées sous leur sort de fabrication.
-- On les passe sous l'objet fabriqué sans attendre que la fenêtre de métier soit rouverte.
local function convertOwnTokens()
  if not (C_TradeSkillUI and (C_TradeSkillUI.GetRecipeOutputItemData or C_TradeSkillUI.GetRecipeItemLink)) then return end
  local changed = false
  for _, own in pairs(ns.char.profs) do
    local seen, seq, touched = {}, {}, false
    for _, e in ipairs(own.seq or {}) do
      local kind, id = M.ParseToken(e.t)
      local t = e.t
      if kind == "s" then
        local item = M.Token("i", outputItem(id))
        if item then
          t, touched = item, true
          local reagents = ns:RetailReagents(id)
          if reagents and #reagents > 0 then ns:StoreReagents(t, reagents) end
        end
      end
      if not seen[t] then
        seen[t] = true
        seq[#seq + 1] = { t = t, c = e.c }
      end
    end
    if touched then
      own.seq, own.n, own.hash = seq, #seq, M.Hash(seq)
      changed = true
    end
  end
  if changed then
    ns:MirrorOwn()
    ns:Announce()
  end
end

-- Rangs sans ouvrir de fenêtre, et métiers abandonnés.
function ns:RefreshOwnRanks()
  local seen, reliable = {}, false
  if GetProfessions and GetProfessionInfo then
    reliable = true
    for _, idx in pairs({ GetProfessions() }) do
      -- Retail : le rang dépend de l'extension affichée ; seule la fenêtre de métier le donne.
      local _, _, _, _, _, _, line = GetProfessionInfo(idx)
      if line and self.ProfessionsByID[line] then seen[line] = {} end
    end
  elseif GetNumSkillLines and GetSkillLineInfo then
    reliable = true
    for i = 1, GetNumSkillLines() do
      local name, isHeader, isExpanded, rank, _, _, max = GetSkillLineInfo(i)
      if isHeader and not isExpanded then reliable = false end
      local p = not isHeader and self:ProfessionByName(name)
      if p then seen[p] = { rank = rank, max = max } end
    end
  end
  local changed = false
  for p, own in pairs(self.char.profs) do
    local s = seen[p]
    if s then
      if s.rank and s.rank < (own.rank or 0) then
        own.seq, own.n, own.hash = {}, 0, M.Hash({})
        changed = true
      end
      if s.rank and (s.rank ~= own.rank or s.max ~= own.max) then
        own.rank, own.max = s.rank, s.max
        changed = true
      end
    elseif reliable then
      self.char.profs[p] = nil
      changed = true
    end
  end
  if changed then
    self:MirrorOwn()
    self:Announce()
  end
end

local scanPending = {}
local function later(key, fn)
  if scanPending[key] then return end
  scanPending[key] = true
  C_Timer.After(0.5, function() scanPending[key] = false; fn() end)
end

function ns:InitScan()
  local f = CreateFrame("Frame")
  local retail = not GetNumTradeSkills
  local events = retail and { "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "SKILL_LINES_CHANGED" }
    or { "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE", "SKILL_LINES_CHANGED" }
  for _, e in ipairs(events) do pcall(f.RegisterEvent, f, e) end
  f:SetScript("OnEvent", function(_, event)
    if event == "SKILL_LINES_CHANGED" then
      later("ranks", function() ns:RefreshOwnRanks() end)
    elseif retail then
      later("retail", scanRetail)
    elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
      later("craft", scanCraft)
    else
      later("trade", scanTradeSkill)
    end
  end)
  C_Timer.After(5, function()
    if retail then convertOwnTokens() end
    ns:RefreshOwnRanks()
  end)
end
