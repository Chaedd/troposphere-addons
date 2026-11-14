-- GuildCraft : échanges avec la guilde (messages d'addon, canal GUILD uniquement).
--
--   R|                           « annoncez vos métiers »
--   H|<métier>:<rang>:<max>:<nb>:<empreinte>;...   mes métiers (« - » si aucun)
--   G|<membre>|<métier>|<empreinte>               « <membre>, envoie ta liste pour ce métier »
--   D|<métier>|<empreinte>|<i>|<total>|<jetons>   un morceau de ma liste
--
-- L'empreinte change dès qu'une recette s'ajoute : on ne redemande une liste que si elle a
-- changé. Tout passe par la guilde, donc une liste envoyée profite à tous les membres équipés.
local _, ns = ...
local M = ns.Model
local PREFIX = "GUILDCRAFT1"
local SEND_INTERVAL = 0.5

local queue = {}
local rates = {}
local partials = {}       -- membre|métier|empreinte → { n, got, parts, t }
local asked = {}          -- membre|métier|empreinte → moment de la dernière demande (la mienne ou une autre)
local sentData = {}       -- métier → moment de mon dernier envoi
local wanted, wantScheduled = {}, false
local announceScheduled = false
ns.heard = {}             -- membres entendus depuis la connexion

function ns:ResetSync()
  queue, rates, partials, asked, sentData, wanted = {}, {}, {}, {}, {}, {}
  self.heard = {}
  self.lastRequest, self.lastAnnounce = nil, nil
end

local function enqueue(msg) queue[#queue + 1] = { msg = msg, tries = 0 } end

local function announceNow()
  announceScheduled = false
  if not ns.scope then return end
  local list = {}
  for p, own in pairs(ns.char.profs) do
    list[#list + 1] = { p = p, rank = own.rank, max = own.max, n = own.n, hash = own.hash }
  end
  table.sort(list, function(a, b) return a.p < b.p end)
  enqueue("H|" .. M.EncodeAnnounce(list))
  ns.lastAnnounce = GetTime()
end

-- Dit mes métiers à la guilde, une seule fois si plusieurs changements arrivent d'un coup.
function ns:Announce(delay)
  if not self.scope or announceScheduled then return end
  announceScheduled = true
  C_Timer.After(delay or 1, announceNow)
end

-- Demande à toute la guilde d'annoncer ses métiers.
function ns:RequestAll(manual)
  if not self.scope then
    if manual then self:Print("Tu dois être dans une guilde.") end
    return
  end
  local now = GetTime()
  if self.lastRequest and now - self.lastRequest < 30 then
    if manual then self:Print("Demande déjà envoyée il y a quelques secondes, patiente un peu.") end
    return
  end
  self.lastRequest = now
  self.lastRequestTime = GetServerTime()
  enqueue("R|")
  self:Announce(0.1)
  self:Changed()
end

local function flushWanted()
  wantScheduled = false
  if not ns.scope or not ns.guild then wanted = {}; return end
  local now = GetTime()
  for id, w in pairs(wanted) do
    local m = ns.guild.members[w.key]
    local pr = m and m.profs[w.p]
    local partial = partials[id .. "|" .. w.hash]
    local busy = partial and now - partial.t < 10
    local recent = asked[id .. "|" .. w.hash] and now - asked[id .. "|" .. w.hash] < 20
    if pr and pr.want == w.hash and pr.hash ~= w.hash and not busy and not recent then
      asked[id .. "|" .. w.hash] = now
      enqueue("G|" .. M.EncodeRequest(w.key, w.p, w.hash))
    end
  end
  wanted = {}
end

local function want(key, p, hash)
  wanted[key .. "|" .. p] = { key = key, p = p, hash = hash }
  if not wantScheduled then
    wantScheduled = true
    C_Timer.After(1 + math.random() * 3, flushWanted)
  end
end

local function onAnnounce(key, name, body)
  local list = M.DecodeAnnounce(body)
  if not list then return end
  local m = ns:Member(key, name)
  if not m then return end
  m.t = GetServerTime()
  ns.heard[key] = true
  local seen = {}
  for _, e in ipairs(list) do
    seen[e.p] = true
    local pr = m.profs[e.p]
    if not pr then pr = { r = {} }; m.profs[e.p] = pr end
    pr.rank, pr.max = e.rank, e.max
    if e.n == 0 then
      pr.r, pr.n, pr.hash, pr.want = {}, 0, e.hash, nil
    elseif pr.hash ~= e.hash then
      pr.want = e.hash
      want(key, e.p, e.hash)
    end
  end
  for p in pairs(m.profs) do if not seen[p] then m.profs[p] = nil end end
  ns:Changed()
end

local function onRequest(body)
  local key, p, hash = M.DecodeRequest(body)
  if not key then return end
  local now = GetTime()
  asked[key .. "|" .. p .. "|" .. hash] = now
  if key ~= ns.playerKey then return end
  local own = ns.char.profs[p]
  if not own or (own.n or 0) == 0 then return end
  if sentData[p] and now - sentData[p] < 20 then return end
  sentData[p] = now
  for _, chunk in ipairs(M.EncodeData(p, own.hash, own.r)) do enqueue("D|" .. chunk) end
end

local function onData(key, name, body)
  local p, hash, i, n, tokens = M.DecodeData(body)
  if not p then return end
  local id = key .. "|" .. p .. "|" .. hash
  local now = GetTime()
  local part = partials[id]
  if not part or part.n ~= n or now - part.t > 60 then
    part = { n = n, got = 0, parts = {} }
    partials[id] = part
  end
  part.t = now
  if not part.parts[i] then
    part.parts[i] = tokens
    part.got = part.got + 1
  end
  if part.got < n then return end
  partials[id] = nil

  local set, count = {}, 0
  for _, list in ipairs(part.parts) do
    for _, t in ipairs(list) do
      if not set[t] then set[t] = true; count = count + 1 end
    end
  end
  if count > M.MAX_RECIPES or M.Hash(set) ~= hash then return end
  local m = ns:Member(key, name)
  if not m then return end
  m.t = GetServerTime()
  local pr = m.profs[p]
  if not pr then pr = { rank = 0, max = 0 }; m.profs[p] = pr end
  pr.r, pr.n, pr.hash = set, count, hash
  if pr.want == hash then pr.want = nil end
  ns:Changed()
end

function ns:Receive(prefix, msg, channel, sender)
  if prefix ~= PREFIX or channel ~= "GUILD" or not self.guild then return end
  if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
  if type(msg) ~= "string" or #msg > 255 then return end
  local key = M.Key(sender)
  if not key or key == self.playerKey then return end
  local name = (self.roster[key] and self.roster[key].name) or M.Pretty(sender)

  local now = GetTime()
  local rate = rates[key]
  if not rate or now - rate.start > 2 then rate = { start = now, n = 0 }; rates[key] = rate end
  rate.n = rate.n + 1
  if rate.n > 30 then return end

  local kind, body = msg:match("^([RHGD])|(.*)$")
  if kind == "R" then
    if not self.lastAnnounce or now - self.lastAnnounce > 15 then self:Announce(1 + math.random() * 3) end
  elseif kind == "H" then
    onAnnounce(key, name, body)
  elseif kind == "G" then
    onRequest(body)
  elseif kind == "D" then
    onData(key, name, body)
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
    -- Premier tour de table quelques secondes après la connexion, puis toutes les 30 minutes.
    if ns.scope and not ns.lastRequest and started > 8 then ns:RequestAll() end
    if periodic > 1800 then periodic = 0; ns:RequestAll() end
  end)
end
