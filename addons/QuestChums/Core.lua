-- QuestChums : démarrage, sauvegarde et liste des membres de la guilde.
local ADDON, ns = ...
QuestChums = ns
local M = ns.Model

local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
ns.version = GetMeta and GetMeta(ADDON, "Version") or "?"
ns.roster = {}      -- clé → { name, level, class, online }
ns.defaults = { showOffline = true, minimapAngle = 200 }

local KEEP_DAYS = 30        -- au-delà, l'état d'un membre pour une quête est oublié
ns.MAX_PER_MEMBER = 600     -- quêtes gardées par membre, au plus

function ns:Print(s) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffQuestChums|r : " .. s) end

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

-- Oublie les états trop vieux et les membres qui n'ont plus rien.
local function prune(guild)
  local limit = GetServerTime() - KEEP_DAYS * 86400
  for key, m in pairs(guild.members) do
    local n = 0
    for id, e in pairs(m.q or {}) do
      if type(e) ~= "table" or (e.t or 0) < limit or not M.ValidState(e.s) then m.q[id] = nil else n = n + 1 end
    end
    m.n = n
    if n == 0 then guild.members[key] = nil end
  end
end

function ns:RefreshGuild()
  local guild = IsInGuild() and GetGuildInfo("player")
  local scope = guild and (self:Realm() .. ":" .. (UnitFactionGroup("player") or "") .. ":" .. guild)
  if scope ~= self.scope then
    self.scope, self.guild = scope, nil
    if scope then
      QuestChumsDB.guilds[scope] = QuestChumsDB.guilds[scope] or { members = {} }
      self.guild = QuestChumsDB.guilds[scope]
      self.guild.members = self.guild.members or {}
      prune(self.guild)
    end
    if self.ResetSync then self:ResetSync() end
  end

  local roster = {}
  if scope then
    for i = 1, GetNumGuildMembers() do
      local name, _, _, level, _, _, _, _, online, _, class = GetGuildRosterInfo(i)
      local key = M.Key(name)
      if key and key ~= self.playerKey then
        roster[key] = { name = M.Pretty(name), level = level, class = class, online = not not online }
      end
    end
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
    QuestChumsDB = QuestChumsDB or {}
    QuestChumsDB.guilds = QuestChumsDB.guilds or {}
    QuestChumsDB.options = QuestChumsDB.options or {}
    QuestChumsCharDB = QuestChumsCharDB or {}
    QuestChumsCharDB.available = QuestChumsCharDB.available or {}
    ns.options = QuestChumsDB.options
    for k, v in pairs(ns.defaults) do if ns.options[k] == nil then ns.options[k] = v end end
    frame:UnregisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
  elseif event == "PLAYER_LOGIN" then
    ns.player = ns:PlayerName()
    ns.playerKey = M.Key(ns.player)
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
    frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    ns:RefreshGuild()
    ns:InitQuests()
    ns:InitSync()
    ns:InitMinimap()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
    ns:Print("v" .. ns.version .. " chargé. /questchums pour ouvrir la fenêtre.")
  elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
    ns:RefreshGuild()
  end
end)

SLASH_QUESTCHUMS1 = "/questchums"
SLASH_QUESTCHUMS2 = "/qc"
SlashCmdList.QUESTCHUMS = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "actualiser" or msg == "sync" then
    ns:RequestStatus(true)
  else
    ns:Toggle()
  end
end
