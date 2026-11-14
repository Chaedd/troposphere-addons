-- GuildCraft : format des messages et règles de données.
-- Aucune fonction du jeu ici : ce fichier se teste hors de WoW.
--
-- Une recette est un « jeton » : une lettre puis un nombre en base 36, sans zéro devant.
--   i<n> : la recette fabrique l'objet n        s<n> : la recette est le sort n (enchantements…)
local _, ns = ...
ns = ns or {}

local M = {}
ns.Model = M

M.MAX_LEN = 200          -- octets de jetons par message de données (limite du jeu : 255)
M.MAX_RECIPES = 2000     -- recettes par métier, au plus
M.MAX_PARTS = 80         -- messages par métier, au plus
M.MAX_PROFS = 12

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

function M.ToBase36(n)
  n = math.floor(n)
  if n <= 0 then return "0" end
  local s = ""
  while n > 0 do
    local d = n % 36
    s = DIGITS:sub(d + 1, d + 1) .. s
    n = (n - d) / 36
  end
  return s
end

function M.ValidID(id)
  return type(id) == "number" and id >= 1 and id < 1e8 and id == math.floor(id)
end

function M.Token(kind, id)
  if (kind ~= "i" and kind ~= "s") or not M.ValidID(id) then return nil end
  return kind .. M.ToBase36(id)
end

function M.ParseToken(t)
  if type(t) ~= "string" or #t > 7 then return nil end
  local kind, rest = t:match("^([is])([1-9a-z][0-9a-z]*)$")
  if not kind then return nil end
  local id = tonumber(rest, 36)
  if not M.ValidID(id) then return nil end
  return kind, id
end

function M.SortedTokens(set)
  local list = {}
  for t in pairs(set or {}) do list[#list + 1] = t end
  table.sort(list)
  return list
end

-- Une liste de recettes est rangée comme dans la fenêtre de métier : une suite de
-- { t = jeton, c = catégorie }, dans l'ordre du jeu. Sur le canal, la catégorie passe
-- en marqueur « =Nom » devant ses recettes.
function M.CleanCategory(name)
  if type(name) ~= "string" then return "" end
  name = name:gsub("[,|;=%c]", " "):match("^%s*(.-)%s*$")
  if #name > 40 then name = name:sub(1, 40) end
  return name
end

function M.SeqItems(seq)
  local items, cat = {}, nil
  for _, e in ipairs(seq or {}) do
    local c = M.CleanCategory(e.c)
    if c ~= cat then
      cat = c
      items[#items + 1] = "=" .. c
    end
    items[#items + 1] = e.t
  end
  return items
end

function M.ItemsToSeq(items)
  local seq, seen, cat = {}, {}, ""
  for _, item in ipairs(items) do
    if item:sub(1, 1) == "=" then
      cat = item:sub(2)
    elseif not seen[item] then
      seen[item] = true
      seq[#seq + 1] = { t = item, c = cat }
    end
  end
  return seq
end

function M.SeqSet(seq)
  local set = {}
  for _, e in ipairs(seq or {}) do set[e.t] = true end
  return set
end

-- Ancienne sauvegarde (jetons sans ordre) → liste rangée, sans catégorie.
function M.SetToSeq(set)
  local seq = {}
  for _, t in ipairs(M.SortedTokens(set)) do seq[#seq + 1] = { t = t, c = "" } end
  return seq
end

-- Empreinte d'une liste rangée : deux membres qui ont la même savent les mêmes recettes.
function M.Hash(seq)
  local h = 5381
  for _, item in ipairs(M.SeqItems(seq)) do
    for i = 1, #item do h = (h * 33 + item:byte(i)) % 2147483647 end
    h = (h * 33 + 44) % 2147483647
  end
  return M.ToBase36(h)
end

-- Fusionne plusieurs listes rangées en gardant l'ordre de chacune : une recette inconnue
-- se place juste après celle qui la précède dans sa liste, une catégorie aussi.
-- La première liste qui donne une catégorie à une recette l'emporte.
-- Renvoie les catégories dans l'ordre, et pour chacune ses jetons dans l'ordre.
function M.MergeLayouts(layouts)
  local cats, lists, catOf = {}, {}, {}
  local function indexOf(list, value)
    for i, v in ipairs(list) do if v == value then return i end end
  end
  for _, seq in ipairs(layouts) do
    local prevCat, prevInCat = nil, {}
    for _, e in ipairs(seq) do
      local c = catOf[e.t] or M.CleanCategory(e.c)
      if not lists[c] then
        local pos = prevCat and indexOf(cats, prevCat)
        table.insert(cats, pos and pos + 1 or #cats + 1, c)
        lists[c] = {}
      end
      if not catOf[e.t] then
        catOf[e.t] = c
        local after = prevInCat[c] and indexOf(lists[c], prevInCat[c])
        table.insert(lists[c], after and after + 1 or 1, e.t)
      end
      prevCat, prevInCat[c] = c, e.t
    end
  end
  return cats, lists
end

function M.FlattenLayout(cats, lists, max)
  local seq = {}
  for _, c in ipairs(cats) do
    for _, t in ipairs(lists[c]) do
      if max and #seq >= max then return seq end
      seq[#seq + 1] = { t = t, c = c }
    end
  end
  return seq
end

-- Composants d'une recette : "<jeton>|2c4x3;1kpx1" (objet en base 36 × quantité), "-" si aucun.
M.MAX_REAGENTS = 12

function M.EncodeReagents(token, list)
  local items = {}
  for _, r in ipairs(list or {}) do
    if M.ValidID(r.id) and type(r.n) == "number" and r.n >= 1 and r.n < 1000 then
      items[#items + 1] = M.ToBase36(r.id) .. "x" .. math.floor(r.n)
    end
    if #items >= M.MAX_REAGENTS then break end
  end
  return token .. "|" .. (#items > 0 and table.concat(items, ";") or "-")
end

function M.DecodeReagents(s)
  if type(s) ~= "string" or #s > 255 then return nil end
  local token, body = s:match("^([^|]+)|(.+)$")
  if not token or not M.ParseToken(token) then return nil end
  local list = {}
  if body ~= "-" then
    for item in body:gmatch("[^;]+") do
      local id, n = item:match("^([1-9a-z][0-9a-z]*)x(%d+)$")
      id, n = id and tonumber(id, 36), tonumber(n)
      if not M.ValidID(id) or not n or n < 1 or n >= 1000 then return nil end
      list[#list + 1] = { id = id, n = n }
      if #list > M.MAX_REAGENTS then return nil end
    end
  end
  return token, list
end

function M.Count(set)
  local n = 0
  for _ in pairs(set or {}) do n = n + 1 end
  return n
end

-- Découpe des éléments en morceaux "a,b,c" de maxLen octets au plus.
function M.Chunk(items, maxLen)
  maxLen = maxLen or M.MAX_LEN
  local out, cur, len = {}, {}, 0
  for _, item in ipairs(items) do
    local add = #item + (#cur > 0 and 1 or 0)
    if #cur > 0 and len + add > maxLen then
      out[#out + 1] = table.concat(cur, ",")
      cur, len, add = {}, 0, #item
    end
    cur[#cur + 1] = item
    len = len + add
  end
  if #cur > 0 then out[#out + 1] = table.concat(cur, ",") end
  return out
end

local function validHash(h) return type(h) == "string" and h:match("^[0-9a-z]+$") and #h <= 7 end
local function validNum(n, max) return type(n) == "number" and n >= 0 and n <= max and n == math.floor(n) end

-- Annonce : "171:285:300:120:abc12;333:150:225:40:x9" (métier:rang:max:recettes:empreinte), "-" si aucun.
function M.EncodeAnnounce(list)
  local items = {}
  for _, e in ipairs(list) do
    if validNum(e.p, 99999) and validHash(e.hash) then
      items[#items + 1] = e.p .. ":" .. math.floor(e.rank or 0) .. ":" .. math.floor(e.max or 0)
        .. ":" .. math.floor(e.n or 0) .. ":" .. e.hash
    end
  end
  if #items == 0 then return "-" end
  return table.concat(items, ";")
end

function M.DecodeAnnounce(s)
  if type(s) ~= "string" or #s > 255 then return nil end
  local out = {}
  if s == "-" then return out end
  for item in s:gmatch("[^;]+") do
    local p, rank, max, n, hash = item:match("^(%d+):(%d+):(%d+):(%d+):([0-9a-z]+)$")
    p, rank, max, n = tonumber(p), tonumber(rank), tonumber(max), tonumber(n)
    if not (validNum(p, 99999) and validNum(rank, 10000) and validNum(max, 10000)
      and validNum(n, M.MAX_RECIPES) and validHash(hash)) then return nil end
    out[#out + 1] = { p = p, rank = rank, max = max, n = n, hash = hash }
    if #out > M.MAX_PROFS then return nil end
  end
  return out
end

-- Demande de liste : "<clé du membre>|<métier>|<empreinte>".
function M.EncodeRequest(key, p, hash) return key .. "|" .. p .. "|" .. hash end

function M.DecodeRequest(s)
  if type(s) ~= "string" or #s > 255 then return nil end
  local key, p, hash = s:match("^([^|]+)|(%d+)|([0-9a-z]+)$")
  p = tonumber(p)
  if not key or not validNum(p, 99999) or not validHash(hash) then return nil end
  return key, p, hash
end

-- Données : "<métier>|<empreinte>|<morceau>|<total>|=Potions,i1a,s2b,=Élixirs,…".
function M.EncodeData(p, hash, seq)
  local chunks = M.Chunk(M.SeqItems(seq))
  local out = {}
  for i, c in ipairs(chunks) do out[i] = p .. "|" .. hash .. "|" .. i .. "|" .. #chunks .. "|" .. c end
  return out
end

function M.DecodeData(s)
  if type(s) ~= "string" or #s > 255 then return nil end
  local p, hash, i, n, body = s:match("^(%d+)|([0-9a-z]+)|(%d+)|(%d+)|(.+)$")
  p, i, n = tonumber(p), tonumber(i), tonumber(n)
  if not validNum(p, 99999) or not validHash(hash) or not validNum(n, M.MAX_PARTS)
    or not validNum(i, n) or i < 1 then return nil end
  local items = {}
  for t in body:gmatch("[^,]+") do
    if t:sub(1, 1) == "=" then
      if #t > 41 or t:find("[|;=%c]", 2) then return nil end
    elseif not M.ParseToken(t) then
      return nil
    end
    items[#items + 1] = t
  end
  if #items == 0 then return nil end
  return p, hash, i, n, items
end

-- Noms : même règle que QuestChums. Sur Forever, un personnage s'appelle « Prénom Nom »,
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
  local key = string.lower(M.CharacterName(name) or name)
  if key:find("|") then return nil end
  return key
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
