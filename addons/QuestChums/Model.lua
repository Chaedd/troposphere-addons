-- QuestChums : format des messages et règles de données.
-- Aucune fonction du jeu ici : ce fichier se teste hors de WoW.
--
-- État d'un membre pour une quête (code court, envoyé tel quel sur le canal de guilde) :
--   H0 à H100 : il a la quête, progression en %       HR : il a la quête, prête à rendre
--   P : il peut la prendre (vue chez un PNJ ou sur sa carte, ou quête précédente de la suite faite)
--   D : il l'a déjà faite        X : il lui manque la quête précédente de la suite
--   N : il ne l'a pas, et son jeu ne dit pas s'il peut la prendre
local _, ns = ...
ns = ns or {}

local M = {}
ns.Model = M

M.MAX_IDS = 40       -- quêtes par message reçu, au plus
M.MAX_LEN = 240      -- octets de données par message (limite du jeu : 255)

function M.ValidID(id)
  return type(id) == "number" and id >= 1 and id < 1e7 and id == math.floor(id)
end

function M.ValidState(s)
  if type(s) ~= "string" then return false end
  if s == "P" or s == "D" or s == "X" or s == "N" or s == "HR" then return true end
  local n = s:match("^H(%d%d?%d?)$")
  return n ~= nil and tonumber(n) <= 100
end

-- "has" : l'a aussi, "can" : peut la faire, "not" : ne l'a pas.
function M.Category(s)
  if type(s) ~= "string" then return nil end
  local c = s:sub(1, 1)
  if c == "H" then return "has" end
  if c == "P" then return "can" end
  if c == "D" or c == "X" or c == "N" then return "not" end
end

-- Pour trier « l'a aussi » : prête à rendre d'abord, puis la plus avancée.
function M.ProgressValue(s)
  if s == "HR" then return 101 end
  return tonumber(type(s) == "string" and s:match("^H(%d+)$")) or -1
end

-- Objectifs de C_QuestLog.GetQuestObjectives → code H<n>.
function M.ProgressState(objectives, ready)
  if ready then return "HR" end
  local sum, n = 0, 0
  for _, o in ipairs(objectives or {}) do
    local req = tonumber(o.numRequired) or 0
    local done = tonumber(o.numFulfilled) or 0
    local part
    if o.finished then part = 1
    elseif req > 0 then part = math.min(done / req, 1)
    else part = 0 end
    sum, n = sum + part, n + 1
  end
  if n == 0 then return "H0" end
  return "H" .. math.floor(sum / n * 100)
end

-- Découpe des éléments déjà encodés en morceaux "a,b,c" de maxLen octets au plus.
function M.Chunk(items, maxLen)
  maxLen = maxLen or M.MAX_LEN
  local out, cur = {}, {}
  local len = 0
  for _, item in ipairs(items) do
    local add = #item + (#cur > 0 and 1 or 0)
    if #cur > 0 and (len + add > maxLen or #cur >= M.MAX_IDS) then
      out[#out + 1] = table.concat(cur, ",")
      cur, len, add = {}, 0, #item
    end
    cur[#cur + 1] = item
    len = len + add
  end
  if #cur > 0 then out[#out + 1] = table.concat(cur, ",") end
  return out
end

-- Demande : "12345:1429,678:0" (quête : carte où elle se trouve, 0 si inconnue).
function M.EncodeQuery(list)
  local items = {}
  for _, q in ipairs(list) do
    if M.ValidID(q.id) then
      local map = tonumber(q.map) or 0
      if map < 0 or map >= 1e6 or map ~= math.floor(map) then map = 0 end
      items[#items + 1] = q.id .. ":" .. map
    end
  end
  return M.Chunk(items)
end

function M.DecodeQuery(s)
  if type(s) ~= "string" or #s > 255 then return nil end
  local out = {}
  for item in s:gmatch("[^,]+") do
    local id, map = item:match("^(%d+):(%d+)$")
    id, map = tonumber(id), tonumber(map)
    if not M.ValidID(id) or not map or map >= 1e6 then return nil end
    out[#out + 1] = { id = id, map = map }
    if #out > M.MAX_IDS then return nil end
  end
  if #out == 0 then return nil end
  return out
end

-- Réponse ou mise à jour : "12345=H40,678=P".
function M.EncodeStates(list)
  local items = {}
  for _, q in ipairs(list) do
    if M.ValidID(q.id) and M.ValidState(q.s) then items[#items + 1] = q.id .. "=" .. q.s end
  end
  return M.Chunk(items)
end

function M.DecodeStates(s)
  if type(s) ~= "string" or #s > 255 then return nil end
  local out = {}
  for item in s:gmatch("[^,]+") do
    local id, st = item:match("^(%d+)=(%w+)$")
    id = tonumber(id)
    if not M.ValidID(id) or not M.ValidState(st) then return nil end
    out[#out + 1] = { id = id, s = st }
    if #out > M.MAX_IDS then return nil end
  end
  if #out == 0 then return nil end
  return out
end

-- Noms : même règle que Red Flag. Sur Forever, un personnage s'appelle « Prénom Nom »,
-- et CHAT_MSG_ADDON y ajoute « -Royaume ». On garde « Prénom-Nom » comme identité.
function M.CharacterName(s)
  if type(s) ~= "string" or #s > 100 then return nil end
  s = s:match("^%s*(.-)%s*$")
  local first, surname, suffix = s:match("^([^%s%-]+)[ %-]([^%s%-]+)(.*)$")
  if not first or (suffix ~= "" and not suffix:match("^%-[^%s|%%:%c]+$")) then return nil end
  if first:find("[|%%:%c%d]") or surname:find("[|%%:%c%d]") then return nil end
  return first .. "-" .. surname
end

function M.Key(name)
  if type(name) ~= "string" then return nil end
  return string.lower(M.CharacterName(name) or name)
end

function M.Pretty(name)
  return ((M.CharacterName(name) or name or ""):gsub("%-", " "))
end

function M.Age(seconds)
  seconds = math.max(0, seconds or 0)
  if seconds < 3600 then return "il y a " .. math.max(1, math.floor(seconds / 60)) .. " min" end
  if seconds < 86400 then return "il y a " .. math.floor(seconds / 3600) .. " h" end
  return "il y a " .. math.floor(seconds / 86400) .. " j"
end

return M
