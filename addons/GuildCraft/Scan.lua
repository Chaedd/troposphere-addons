-- GuildCraft : lecture de mes métiers.
-- Les recettes ne se lisent que fenêtre de métier ouverte. Sur Classic, la fenêtre peut
-- être filtrée (catégories repliées, « composants disponibles ») : on ajoute alors ce qu'on
-- voit à ce qu'on savait déjà, sans rien retirer. Une recette ne s'oublie pas, sauf en
-- abandonnant le métier : on repart de zéro si le rang baisse ou si le métier disparaît.
local _, ns = ...
local M = ns.Model

local function itemToken(link)
  local id = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)"))
  return id and M.Token("i", id)
end

local function spellToken(link)
  if type(link) ~= "string" then return nil end
  local id = tonumber(link:match("|Henchant:(%d+)") or link:match("|Hspell:(%d+)") or link:match("|Htrade:[^:]*:(%d+)"))
  return id and M.Token("s", id)
end

-- Enregistre ce que je sais d'un métier ; complete = la liste lue est entière.
function ns:UpdateOwn(p, rank, max, found, complete)
  local own = self.char.profs[p]
  local set = {}
  if own and not complete and not (rank and own.rank and rank < own.rank) then
    for t in pairs(own.r or {}) do set[t] = true end
  end
  local n = M.Count(set)
  for t in pairs(found) do
    if not set[t] and n < M.MAX_RECIPES then set[t] = true; n = n + 1 end
  end
  local hash = M.Hash(set)
  rank, max = rank or (own and own.rank) or 0, max or (own and own.max) or 0
  if own and own.hash == hash and own.rank == rank and own.max == max then return end
  self.char.profs[p] = { rank = rank, max = max, r = set, n = n, hash = hash }
  self:MirrorOwn()
  self:Announce()
end

-- Classic : fenêtre de métier (TradeSkill).
local function scanTradeSkill()
  if not GetTradeSkillLine or not GetNumTradeSkills then return end
  if IsTradeSkillLinked and IsTradeSkillLinked() then return end
  local name, rank, max = GetTradeSkillLine()
  local p = ns:ProfessionByName(name)
  if not p then return end
  local found = {}
  for i = 1, GetNumTradeSkills() do
    local rname, kind = GetTradeSkillInfo(i)
    if rname and kind ~= "header" and kind ~= "subheader" then
      local t = itemToken(GetTradeSkillItemLink and GetTradeSkillItemLink(i))
        or spellToken(GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i))
      if t then found[t] = true end
    end
  end
  ns:UpdateOwn(p, rank, max, found, false)
end

-- Classic : enchantement passe par l'ancienne fenêtre « Craft ».
local function scanCraft()
  if not GetCraftDisplaySkillLine or not GetNumCrafts then return end
  local name, rank, max = GetCraftDisplaySkillLine()
  local p = ns:ProfessionByName(name)
  if not p then return end
  local found = {}
  for i = 1, GetNumCrafts() do
    local cname, _, kind = GetCraftInfo(i)
    if cname and kind ~= "header" then
      local link = GetCraftItemLink and GetCraftItemLink(i)
      local t = spellToken(link) or itemToken(link)
        or spellToken(GetCraftRecipeLink and GetCraftRecipeLink(i))
      if t then found[t] = true end
    end
  end
  ns:UpdateOwn(p, rank, max, found, false)
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
  local found = {}
  for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
    local r = T.GetRecipeInfo(id)
    if r and r.learned and not r.isRecraft and not r.isDummyRecipe then
      local t = M.Token("s", id)
      if t then found[t] = true end
    end
  end
  ns:UpdateOwn(p, rank, max, found, true)
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
        own.r, own.n, own.hash = {}, 0, M.Hash({})
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
  C_Timer.After(5, function() ns:RefreshOwnRanks() end)
end
