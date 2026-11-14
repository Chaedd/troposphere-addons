-- GuildCraft : démarrage, sauvegarde, métiers connus et liste des membres de la guilde.
local ADDON, ns = ...
GuildCraft = ns
local M = ns.Model

local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
ns.version = GetMeta and GetMeta(ADDON, "Version") or "?"
ns.roster = {}      -- clé → { name, level, class, online }
ns.defaults = { showOffline = true, minimapAngle = 220 }

local KEEP_DAYS = 90        -- un membre muet depuis plus longtemps est oublié

-- Métiers qui ont des recettes. L'identifiant est celui de la ligne de compétence du jeu.
ns.PROFESSIONS = {
  { id = 171, spells = { 2259 }, names = { "Alchimie", "Alchemy" }, icon = "Interface\\Icons\\Trade_Alchemy" },
  { id = 164, spells = { 2018 }, names = { "Forge", "Blacksmithing" }, icon = "Interface\\Icons\\Trade_BlackSmithing" },
  { id = 333, spells = { 7411 }, names = { "Enchantement", "Enchanting" }, icon = "Interface\\Icons\\Trade_Engraving" },
  { id = 202, spells = { 4036 }, names = { "Ingénierie", "Engineering" }, icon = "Interface\\Icons\\Trade_Engineering" },
  { id = 165, spells = { 2108 }, names = { "Travail du cuir", "Leatherworking" }, icon = "Interface\\Icons\\Trade_LeatherWorking" },
  { id = 197, spells = { 3908 }, names = { "Couture", "Tailoring" }, icon = "Interface\\Icons\\Trade_Tailoring" },
  { id = 186, spells = { 2575, 2656 }, names = { "Minage", "Mining", "Fondre", "Smelting" }, icon = "Interface\\Icons\\Trade_Mining" },
  { id = 185, spells = { 2550 }, names = { "Cuisine", "Cooking" }, icon = "Interface\\Icons\\INV_Misc_Food_15" },
  { id = 129, spells = { 3273 }, names = { "Secourisme", "First Aid" }, icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
  { id = 755, spells = { 25229 }, names = { "Joaillerie", "Jewelcrafting" }, icon = "Interface\\Icons\\INV_Misc_Gem_01" },
  { id = 773, spells = { 45357 }, names = { "Calligraphie", "Inscription" }, icon = "Interface\\Icons\\INV_Inscription_Tradeskill01" },
  { id = 40, spells = { 2842 }, names = { "Poisons" }, icon = "Interface\\Icons\\Trade_BrewPoison" },
}
ns.ProfessionsByID = {}
for _, p in ipairs(ns.PROFESSIONS) do ns.ProfessionsByID[p.id] = p end

function ns:Print(s) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffGuildCraft|r : " .. s) end

function ns:SpellInfo(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, id)
    if ok and type(info) == "table" then return info.name, info.iconID end
  end
  if GetSpellInfo then
    local name, _, icon = GetSpellInfo(id)
    return name, icon
  end
end

-- Noms traduits par le jeu, pour reconnaître la fenêtre de métier ouverte.
local byName = {}
local function buildNames()
  for _, p in ipairs(ns.PROFESSIONS) do
    for _, n in ipairs(p.names) do byName[n:lower()] = p.id end
    for _, spell in ipairs(p.spells) do
      local name, icon = ns:SpellInfo(spell)
      if name then
        byName[name:lower()] = p.id
        p.localName = p.localName or name
        p.gameIcon = p.gameIcon or icon
      end
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
      local ok, name = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, p.id)
      if ok and type(name) == "string" and name ~= "" then
        byName[name:lower()] = p.id
        p.localName = name
      end
    end
  end
end

function ns:ProfessionByName(name)
  if type(name) ~= "string" then return nil end
  return byName[name:lower()]
end

function ns:ProfessionName(id)
  local p = self.ProfessionsByID[id]
  return p and (p.localName or p.names[1]) or ("Métier " .. tostring(id))
end

function ns:ProfessionIcon(id)
  local p = self.ProfessionsByID[id]
  return p and (p.gameIcon or p.icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function ns:Realm()
  return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName() or ""):gsub("%s", "")
end

function ns:PlayerName()
  local name, realm = UnitFullName("player")
  if issecretvalue and (issecretvalue(name) or issecretvalue(realm)) then return nil end
  if not name then return nil end
  if name:find("[ %-]") then return name end
  return name .. "-" .. (realm and realm ~= "" and realm or self:Realm())
end

-- Fiche d'un membre dans la sauvegarde de la guilde (créée au besoin).
function ns:Member(key, name)
  local guild = self.guild
  if not guild or not key then return nil end
  local m = guild.members[key]
  if not m then m = { profs = {} }; guild.members[key] = m end
  m.profs = m.profs or {}
  if name then m.name = name end
  return m
end

-- Recopie mes métiers dans la sauvegarde de la guilde : je m'affiche comme les autres.
function ns:MirrorOwn()
  if not self.guild or not self.playerKey then return end
  local m = self:Member(self.playerKey, M.Pretty(self.player))
  m.t = GetServerTime()
  m.profs = {}
  for p, own in pairs(self.char.profs) do
    m.profs[p] = { rank = own.rank, max = own.max, n = own.n, hash = own.hash, seq = own.seq }
  end
  self:Changed()
end

-- Composants : ce sont des données du jeu, les mêmes pour tous, gardées pour toutes les guildes.
function ns:StoreReagents(token, list)
  if not token or type(list) ~= "table" then return end
  local old = GuildCraftDB.reagents[token]
  GuildCraftDB.reagents[token] = list
  if not old and self.window and self.window:IsShown() then self:Changed() end
end

function ns:Reagents(token)
  local list = GuildCraftDB.reagents[token]
  if list then return list end
  local kind, id = M.ParseToken(token)
  if kind == "s" and self.RetailReagents then
    list = self:RetailReagents(id)
    if list and #list > 0 then GuildCraftDB.reagents[token] = list; return list end
  end
end

-- Numéro de la recette (son sort de fabrication) : il faut le connaître pour la suivre.
-- Une recette rangée sous son sort le donne directement ; pour un objet, on l'apprend en
-- lisant sa fenêtre de métier, ou d'un membre de la guilde qui l'a lue.
function ns:SetRecipeID(token, id)
  if not token or not M.ValidID(id) or GuildCraftDB.recipeOf[token] == id then return end
  GuildCraftDB.recipeOf[token] = id
  if self.window and self.window:IsShown() then self:Changed() end
end

function ns:RecipeID(token)
  local kind, id = M.ParseToken(token)
  if kind == "s" then return id end
  return GuildCraftDB.recipeOf[token]
end

-- Oublie les membres muets depuis trop longtemps et les données abîmées.
local function prune(guild)
  local limit = GetServerTime() - KEEP_DAYS * 86400
  for key, m in pairs(guild.members) do
    if type(m) ~= "table" or (m.t or 0) < limit or type(m.profs) ~= "table" then
      guild.members[key] = nil
    else
      for p, pr in pairs(m.profs) do
        -- Une liste sans rangement vient de la version 1.0 : elle sera redemandée.
        if type(pr) ~= "table" or type(pr.seq) ~= "table" then m.profs[p] = nil end
      end
    end
  end
end

function ns:RefreshGuild()
  local guild = IsInGuild() and GetGuildInfo("player")
  local scope = guild and (self:Realm() .. ":" .. (UnitFactionGroup("player") or "") .. ":" .. guild)
  if scope ~= self.scope then
    self.scope, self.guild = scope, nil
    if scope then
      GuildCraftDB.guilds[scope] = GuildCraftDB.guilds[scope] or { members = {} }
      self.guild = GuildCraftDB.guilds[scope]
      self.guild.members = self.guild.members or {}
      prune(self.guild)
      self:MirrorOwn()
    end
    if self.ResetSync then self:ResetSync() end
  end

  local roster = {}
  if scope then
    for i = 1, GetNumGuildMembers() do
      local name, _, _, level, _, _, _, _, online, _, class = GetGuildRosterInfo(i)
      local key = M.Key(name)
      if key then
        roster[key] = { name = M.Pretty(name), level = level, class = class, online = not not online }
      end
    end
  end
  if self.playerKey and scope then
    local _, class = UnitClass("player")
    roster[self.playerKey] = roster[self.playerKey]
      or { name = M.Pretty(self.player), level = UnitLevel("player"), class = class, online = true }
    roster[self.playerKey].online = true
  end
  self.roster = roster
  self:Changed()
end

-- Rafraîchit la fenêtre, au plus une fois par fraction de seconde.
function ns:Changed()
  if self.changePending or not self.RefreshUI then return end
  self.changePending = true
  C_Timer.After(0.3, function()
    ns.changePending = false
    ns:RefreshUI()
  end)
end

local frame = CreateFrame("Frame")
ns.events = frame
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    GuildCraftDB = GuildCraftDB or {}
    GuildCraftDB.guilds = GuildCraftDB.guilds or {}
    GuildCraftDB.options = GuildCraftDB.options or {}
    GuildCraftCharDB = GuildCraftCharDB or {}
    GuildCraftCharDB.profs = GuildCraftCharDB.profs or {}
    GuildCraftDB.reagents = GuildCraftDB.reagents or {}
    GuildCraftDB.recipeOf = GuildCraftDB.recipeOf or {}
    GuildCraftCharDB.tracked = GuildCraftCharDB.tracked or {}
    -- Version 1.0 : recettes sans catégorie ; elles seront rangées à la prochaine ouverture du métier.
    for _, own in pairs(GuildCraftCharDB.profs) do
      if type(own.seq) ~= "table" then
        own.seq = M.SetToSeq(own.r)
        own.r = nil
        own.n, own.hash = #own.seq, M.Hash(own.seq)
      end
    end
    ns.char = GuildCraftCharDB
    ns.options = GuildCraftDB.options
    for k, v in pairs(ns.defaults) do if ns.options[k] == nil then ns.options[k] = v end end
    frame:UnregisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
  elseif event == "PLAYER_LOGIN" then
    buildNames()
    ns.player = ns:PlayerName()
    ns.playerKey = M.Key(ns.player)
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
    frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    ns:RefreshGuild()
    ns:InitScan()
    ns:InitSync()
    ns:InitMinimap()
    ns:InitTrack()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
    ns:Print("v" .. ns.version .. " chargé. /guildcraft pour ouvrir la fenêtre.")
    if not next(ns.char.profs) then
      ns:Print("Ouvre une fois la fenêtre de chacun de tes métiers pour partager tes recettes avec la guilde.")
    end
  elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
    ns:RefreshGuild()
  end
end)

SLASH_GUILDCRAFT1 = "/guildcraft"
SLASH_GUILDCRAFT2 = "/artisans"
SlashCmdList.GUILDCRAFT = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "actualiser" or msg == "sync" then
    ns:RequestAll(true)
  else
    ns:Toggle()
  end
end
