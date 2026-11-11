-- QuestChums : échanges avec la guilde (messages d'addon, canal GUILD uniquement).
--
--   Q|<quête>:<carte>,...   « où en êtes-vous sur ces quêtes ? »
--   A|<quête>=<état>,...    réponse à une demande
--   U|<quête>=<état>,...    mon état a changé (quête prise, avancée, rendue, abandonnée)
--
-- Les réponses passent aussi par la guilde : tous les membres équipés en profitent.
-- Seuls les membres connectés ET équipés de QuestChums répondent ; pour les autres,
-- l'addon garde le dernier état reçu, avec sa date.
local _, ns = ...
local M = ns.Model
local PREFIX = "QUESTCHUMS1"
local SEND_INTERVAL = 0.5
local REPEAT_WINDOW = 20      -- on ne répète pas un même état envoyé il y a moins de 20 s

local queue = {}
local rates = {}
local answered = {}           -- id → { s, map, t } : ce que j'ai déjà dit à la guilde
local pending, pendingScheduled = {}, false
local asked, askScheduled = {}, false

function ns:ResetSync()
  queue, rates, answered = {}, {}, {}
  pending, asked = {}, {}
  self.lastRequest = nil
end

local function enqueue(msg) queue[#queue + 1] = { msg = msg, tries = 0 } end

local function broadcast(kind, list)
  local chunks = kind == "Q" and M.EncodeQuery(list) or M.EncodeStates(list)
  for _, c in ipairs(chunks) do enqueue(kind .. "|" .. c) end
end

-- Mon état a changé : on le dit à toute la guilde.
function ns:SendStates(list)
  if not self.scope then return end
  local now, out = GetTime(), {}
  for _, q in ipairs(list) do
    local prev = answered[q.id]
    answered[q.id] = { s = q.s, map = prev and prev.map, t = now }
    out[#out + 1] = q
  end
  broadcast("U", out)
end

-- Une quête que j'ai déjà décrite a pu changer (nouvelle quête disponible sur la carte…).
function ns:RecheckAnswered()
  local changes = {}
  for id, a in pairs(answered) do
    local s = self:OwnState(id, a.map)
    if s ~= a.s then changes[#changes + 1] = { id = id, s = s } end
  end
  if #changes > 0 then self:SendStates(changes) end
end

local function flushAnswers()
  pendingScheduled = false
  if not ns.scope then pending = {}; return end
  local now, out = GetTime(), {}
  for id, map in pairs(pending) do
    local s = ns:OwnState(id, map)
    local prev = answered[id]
    if not prev or prev.s ~= s or now - prev.t >= REPEAT_WINDOW then
      answered[id] = { s = s, map = map > 0 and map or (prev and prev.map), t = now }
      out[#out + 1] = { id = id, s = s }
    end
  end
  pending = {}
  broadcast("A", out)
end

local function flushAsk()
  askScheduled = false
  local list = {}
  for id, map in pairs(asked) do list[#list + 1] = { id = id, map = map } end
  asked = {}
  if ns.scope and #list > 0 then broadcast("Q", list) end
end

-- Demande l'état d'une quête précise (par exemple une quête qu'on vient de prendre).
function ns:AskAbout(id, map)
  if not self.scope then return end
  asked[id] = map or 0
  if not askScheduled then
    askScheduled = true
    C_Timer.After(2, flushAsk)
  end
end

-- Demande l'état de toutes les quêtes du journal.
function ns:RequestStatus(manual)
  if not self.scope then
    if manual then self:Print("Tu dois être dans une guilde.") end
    return
  end
  local now = GetTime()
  if self.lastRequest and now - self.lastRequest < 15 then
    if manual then self:Print("Demande déjà envoyée il y a quelques secondes, patiente un peu.") end
    return
  end
  self.lastRequest = now
  self.lastRequestTime = GetServerTime()
  broadcast("Q", self:MyQuests())
  self:Changed()
end

local function store(key, name, list)
  local guild = ns.guild
  if not guild then return end
  local m = guild.members[key]
  if not m then m = { q = {}, n = 0 }; guild.members[key] = m end
  m.name = name
  local now = GetServerTime()
  m.t = now
  for _, q in ipairs(list) do
    if not m.q[q.id] then
      if (m.n or 0) >= ns.MAX_PER_MEMBER then break end
      m.n = (m.n or 0) + 1
    end
    m.q[q.id] = { s = q.s, t = now }
  end
  ns:Changed()
end

function ns:Receive(prefix, msg, channel, sender)
  if prefix ~= PREFIX or channel ~= "GUILD" or not self.guild then return end
  if type(msg) ~= "string" or #msg > 255 then return end
  local key = M.Key(sender)
  if not key or key == self.playerKey then return end
  local member = self.roster[key]
  if not member then return end

  local now = GetTime()
  local rate = rates[key]
  if not rate or now - rate.start > 2 then rate = { start = now, n = 0 }; rates[key] = rate end
  rate.n = rate.n + 1
  if rate.n > 20 then return end

  local kind, body = msg:match("^([QAU])|(.+)$")
  if kind == "Q" then
    local list = M.DecodeQuery(body)
    if not list then return end
    for _, q in ipairs(list) do pending[q.id] = q.map end
    if not pendingScheduled then
      pendingScheduled = true
      C_Timer.After(1 + math.random() * 3, flushAnswers)
    end
  elseif kind == "A" or kind == "U" then
    local list = M.DecodeStates(body)
    if list then store(key, member.name, list) end
  end
end

function ns:InitSync()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
  local f = CreateFrame("Frame")
  f:RegisterEvent("CHAT_MSG_ADDON")
  f:SetScript("OnEvent", function(_, _, ...) ns:Receive(...) end)

  local elapsed, periodic, started = 0, 0, 0
  f:SetScript("OnUpdate", function(_, dt)
    elapsed, periodic, started = elapsed + dt, periodic + dt, started + dt
    if elapsed >= SEND_INTERVAL then
      elapsed = 0
      local item = queue[1]
      if item and ns.scope then
        local result = C_ChatInfo.SendAddonMessage(PREFIX, item.msg, "GUILD")
        -- Retail renvoie un code (0 = envoyé, 3 et 8 = trop de messages) ; Classic, un booléen.
        local throttled = result == false or result == 3 or result == 8
        item.tries = item.tries + 1
        if not throttled or item.tries >= 5 then table.remove(queue, 1) end
      elseif item then
        queue = {}
      end
    end
    -- Premier tour de table quelques secondes après la connexion, puis toutes les 10 minutes.
    if ns.scope and not ns.lastRequest and started > 8 then ns:RequestStatus() end
    if periodic > 600 then periodic = 0; ns:RequestStatus() end
  end)
end
