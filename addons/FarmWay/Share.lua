-- Partage d'une route sous forme de texte :
--   FW1:<mapID>:<couleur hex>:<nom>:<points>
-- Chaque coordonnée (0 à 9999) tient en 3 caractères ; un point en fait 6.
-- Aucune fonction du jeu ici : ce fichier se teste hors de WoW.
local _, ns = ...

local S = {}
ns.Share = S

local PREFIX = "FW1"
local MAX_POINTS = 5000
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUE = {}
for i = 1, #ALPHABET do VALUE[ALPHABET:sub(i, i)] = i - 1 end

local floor = math.floor

local function char(v)
  return ALPHABET:sub(v + 1, v + 1)
end

local function encodeCoord(x)
  local v = floor(x * 10000 + 0.5)
  if v < 0 then v = 0 elseif v > 9999 then v = 9999 end
  return char(floor(v / 4096)) .. char(floor(v / 64) % 64) .. char(v % 64)
end

local function decodeCoord(s, i)
  local a, b, c = VALUE[s:sub(i, i)], VALUE[s:sub(i + 1, i + 1)], VALUE[s:sub(i + 2, i + 2)]
  if not (a and b and c) then return end
  local v = a * 4096 + b * 64 + c
  if v > 9999 then return end
  return v / 10000
end

local function byte(c)
  local v = floor((c or 1) * 255 + 0.5)
  if v < 0 then v = 0 elseif v > 255 then v = 255 end
  return v
end

function S.Encode(mapID, name, color, points)
  local parts = {}
  for i, p in ipairs(points) do
    parts[i] = encodeCoord(p[1]) .. encodeCoord(p[2])
  end
  color = color or { 1, 1, 1 }
  local hex = string.format("%02x%02x%02x", byte(color[1]), byte(color[2]), byte(color[3]))
  local safeName = (tostring(name or ""):gsub("[:|\r\n]", " "))
  return table.concat({ PREFIX, tostring(mapID), hex, safeName, table.concat(parts) }, ":")
end

-- Renvoie { mapID, name, color, points } ou nil et un code d'erreur
-- ("format", "version" ou "points").
function S.Decode(text)
  if type(text) ~= "string" then return nil, "format" end
  text = text:gsub("[\r\n]", ""):match("^%s*(.-)%s*$")
  local prefix = text:match("^(FW%d+):")
  if not prefix then return nil, "format" end
  if prefix ~= PREFIX then return nil, "version" end
  local mapID, hex, name, data = text:match("^FW1:(%d+):(%x%x%x%x%x%x):([^:]*):([A-Za-z0-9+/]*)$")
  if not mapID then return nil, "format" end
  if #data == 0 or #data % 6 ~= 0 or #data / 6 > MAX_POINTS then return nil, "points" end

  local points = {}
  for i = 1, #data, 6 do
    local x, y = decodeCoord(data, i), decodeCoord(data, i + 3)
    if not (x and y) then return nil, "points" end
    points[#points + 1] = { x, y }
  end

  name = name:match("^%s*(.-)%s*$")
  return {
    mapID = tonumber(mapID),
    name = name ~= "" and name or nil,
    color = {
      tonumber(hex:sub(1, 2), 16) / 255,
      tonumber(hex:sub(3, 4), 16) / 255,
      tonumber(hex:sub(5, 6), 16) / 255,
    },
    points = points,
  }
end
