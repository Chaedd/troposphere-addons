-- Lecture des points de récolte connus de GatherMate2 (s'il est installé).
-- On n'utilise que ses données publiques : GatherMate2.gmdbs, DecodeLoc et GetNameForNode.
local _, ns = ...
local L = ns.L

local S = {}
ns.Sources = S

local TYPE_LABELS = {
  ["Mining"] = "Mining",
  ["Herb Gathering"] = "Herbs",
  ["Fishing"] = "Fishing",
  ["Treasure"] = "Treasure",
  ["Extract Gas"] = "Gas",
  ["Archaeology"] = "Archaeology",
}
local TYPE_ORDER = { "Mining", "Herb Gathering", "Fishing", "Treasure", "Extract Gas", "Archaeology" }

local function gm()
  local g = _G.GatherMate2
  if type(g) == "table" and type(g.gmdbs) == "table" and g.DecodeLoc then return g end
end

function S.Available()
  return gm() ~= nil
end

function S.TypeLabel(dbType)
  return L[TYPE_LABELS[dbType] or dbType]
end

local function zoneNodes(g, dbType, mapID)
  local storage = g.gmdbs[dbType]
  if type(storage) ~= "table" then return end
  local ok, zone = pcall(function() return storage[mapID] end)
  if ok and type(zone) == "table" then return zone end
end

local function typeRank(dbType)
  for i, t in ipairs(TYPE_ORDER) do
    if t == dbType then return i end
  end
  return #TYPE_ORDER + 1
end

-- Liste des ressources présentes dans la zone : { db, id, name, count }.
function S.ListNodeKinds(mapID)
  local g = gm()
  local out = {}
  if not g or not mapID then return out end
  for dbType in pairs(g.gmdbs) do
    local zone = zoneNodes(g, dbType, mapID)
    if zone then
      local counts = {}
      for _, nodeID in pairs(zone) do
        counts[nodeID] = (counts[nodeID] or 0) + 1
      end
      for nodeID, count in pairs(counts) do
        local ok, name = pcall(g.GetNameForNode, g, dbType, nodeID)
        out[#out + 1] = {
          db = dbType,
          id = nodeID,
          name = (ok and name) or ("#" .. tostring(nodeID)),
          count = count,
        }
      end
    end
  end
  table.sort(out, function(a, b)
    local ra, rb = typeRank(a.db), typeRank(b.db)
    if ra ~= rb then return ra < rb end
    if a.db ~= b.db then return a.db < b.db end
    return tostring(a.name) < tostring(b.name)
  end)
  return out
end

-- Tous les points des ressources choisies ({ { db = ..., id = ... }, ... }).
function S.CollectPoints(mapID, selections)
  local g = gm()
  local points = {}
  if not g or not mapID or not selections then return points end
  local wanted = {}
  for _, sel in ipairs(selections) do
    wanted[sel.db] = wanted[sel.db] or {}
    wanted[sel.db][sel.id] = true
  end
  for dbType, ids in pairs(wanted) do
    local zone = zoneNodes(g, dbType, mapID)
    if zone then
      for coord, nodeID in pairs(zone) do
        if ids[nodeID] then
          local x, y = g:DecodeLoc(coord)
          if x and y then points[#points + 1] = { x, y } end
        end
      end
    end
  end
  return points
end
