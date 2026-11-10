local ADDON, ns = ...
local L = ns.L

local FW = CreateFrame("Frame")
ns.FW = FW
_G.FarmWay = FW

FW.COLORS = {
  { 1.00, 0.82, 0.20 }, -- or
  { 0.30, 0.80, 1.00 }, -- bleu
  { 0.40, 1.00, 0.40 }, -- vert
  { 1.00, 0.40, 0.40 }, -- rouge
  { 0.80, 0.50, 1.00 }, -- violet
  { 1.00, 1.00, 1.00 }, -- blanc
}

local DEFAULTS = {
  worldmap = true,
  minimap = true,
  mapWidth = 3,
  minimapWidth = 2,
}

BINDING_HEADER_FARMWAY = "FarmWay"
BINDING_NAME_FARMWAY_ADDPOINT = L["Add my position to the route"]

------------------------------------------------------------------------
-- Utilitaires
------------------------------------------------------------------------

function FW:Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffe0b44cFarmWay|r : " .. tostring(msg))
end

local listeners = {}

-- Les modules (carte, minicarte, panneau) se redessinent quand une route change.
function FW:RegisterCallback(fn)
  listeners[#listeners + 1] = fn
end

function FW:Fire()
  for _, fn in ipairs(listeners) do
    local ok, err = pcall(fn)
    if not ok then geterrorhandler()(err) end
  end
end

local mapReady = {}

-- La carte du monde peut être chargée après l'addon.
function FW:OnWorldMapReady(fn)
  if WorldMapFrame and WorldMapFrame.ScrollContainer then
    fn()
  else
    mapReady[#mapReady + 1] = fn
  end
end

------------------------------------------------------------------------
-- Sauvegarde
------------------------------------------------------------------------

function FW:InitDB()
  if type(FarmWayDB) ~= "table" then FarmWayDB = {} end
  local db = FarmWayDB
  db.version = 1
  if type(db.routes) ~= "table" then db.routes = {} end
  if type(db.settings) ~= "table" then db.settings = {} end
  for k, v in pairs(DEFAULTS) do
    if db.settings[k] == nil then db.settings[k] = v end
  end
  self.db = db
end

------------------------------------------------------------------------
-- Routes : FarmWayDB.routes[mapID][nom] = { points = { {x, y}, ... }, ... }
-- Les coordonnées vont de 0 à 1 sur la carte de la zone ; la route est une boucle.
------------------------------------------------------------------------

function FW:GetRoute(mapID, name)
  local zone = mapID and self.db.routes[mapID]
  return zone and zone[name]
end

function FW:GetRouteNames(mapID)
  local names = {}
  local zone = mapID and self.db.routes[mapID]
  if zone then
    for name in pairs(zone) do names[#names + 1] = name end
  end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  return names
end

function FW:UniqueName(mapID, base)
  base = strtrim(base or "")
  if base == "" then base = L["My route"] end
  local name, i = base, 2
  while self:GetRoute(mapID, name) do
    name = base .. " " .. i
    i = i + 1
  end
  return name
end

local function freeColor(zone)
  local used = {}
  for _, r in pairs(zone) do
    if r.colorIndex then used[r.colorIndex] = true end
  end
  for i = 1, #FW.COLORS do
    if not used[i] then return i end
  end
  return 1
end

function FW:CreateRoute(mapID, name, points, sources)
  local zone = self.db.routes[mapID]
  if not zone then
    zone = {}
    self.db.routes[mapID] = zone
  end
  name = self:UniqueName(mapID, name)
  local ci = freeColor(zone)
  local c = self.COLORS[ci]
  zone[name] = {
    points = points or {},
    color = { c[1], c[2], c[3] },
    colorIndex = ci,
    visible = true,
    sources = sources,
  }
  self:Select(mapID, name)
  return name, zone[name]
end

function FW:DeleteRoute(mapID, name)
  local zone = self.db.routes[mapID]
  if not zone then return end
  zone[name] = nil
  if not next(zone) then self.db.routes[mapID] = nil end
  if self:IsSelected(mapID, name) then
    self.selected = nil
    self.editing = false
  end
  self:Fire()
end

function FW:Select(mapID, name)
  if mapID and name then
    self.selected = { mapID = mapID, name = name }
  else
    self.selected = nil
  end
  self.editing = self.editing and self.selected ~= nil
  self:Fire()
end

function FW:IsSelected(mapID, name)
  local s = self.selected
  return s ~= nil and s.mapID == mapID and s.name == name
end

function FW:GetSelected()
  local s = self.selected
  if not s then return end
  local r = self:GetRoute(s.mapID, s.name)
  if r then return s.mapID, s.name, r end
end

function FW:SetEditing(on)
  self.editing = on and self.selected ~= nil or false
  self:Fire()
end

function FW:CycleColor(mapID, name)
  local r = self:GetRoute(mapID, name)
  if not r then return end
  local i = ((r.colorIndex or 0) % #self.COLORS) + 1
  local c = self.COLORS[i]
  r.colorIndex = i
  r.color = { c[1], c[2], c[3] }
  self:Fire()
end

function FW:SetVisible(mapID, name, visible)
  local r = self:GetRoute(mapID, name)
  if not r then return end
  r.visible = visible and true or false
  self:Fire()
end

------------------------------------------------------------------------
-- Géométrie des cartes
------------------------------------------------------------------------

local yardsCache = {}

-- Taille de la carte en mètres de jeu (yards), ou nil si inconnue.
function FW:GetMapYards(mapID)
  if not mapID then return end
  local c = yardsCache[mapID]
  if c == nil then
    c = false
    if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
      local ok0, _, p0 = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
      local ok1, _, p1 = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 1))
      if ok0 and ok1 and p0 and p1 then
        local a, b = math.abs(p0.x - p1.x), math.abs(p0.y - p1.y)
        if a > 0 and b > 0 then
          -- Une carte de zone est environ 1,5 fois plus large que haute :
          -- on choisit l'axe qui correspond à la largeur.
          if math.abs(a / b - 1.5) < math.abs(b / a - 1.5) then
            c = { a, b }
          else
            c = { b, a }
          end
        end
      end
    end
    yardsCache[mapID] = c
  end
  if c then return c[1], c[2] end
end

-- Rapport largeur / hauteur réel, pour mesurer les distances sur la carte.
function FW:GetAspect(mapID)
  local w, h = self:GetMapYards(mapID)
  if w then return w / h end
  return 1.5
end

function FW:GetPlayerPosition()
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID then return end
  local pos = C_Map.GetPlayerMapPosition(mapID, "player")
  if not pos then return end
  local x, y = pos:GetXY()
  if not x or (x == 0 and y == 0) then return end
  return mapID, x, y
end

------------------------------------------------------------------------
-- Modifications des points
------------------------------------------------------------------------

function FW:AddPoint(mapID, name, x, y)
  local r = self:GetRoute(mapID, name)
  if not r then return end
  ns.Optimize.InsertPoint(r.points, { x, y }, self:GetAspect(mapID))
  self:Fire()
  return #r.points
end

function FW:RemovePoint(mapID, name, index)
  local r = self:GetRoute(mapID, name)
  if not r or not r.points[index] then return end
  table.remove(r.points, index)
  self:Fire()
end

function FW:AddPlayerPosition()
  local mapID, x, y = self:GetPlayerPosition()
  if not mapID then
    self:Print(L["Your position is not available here."])
    return
  end
  local selMap, name = self:GetSelected()
  if selMap ~= mapID then
    local names = self:GetRouteNames(mapID)
    if #names == 1 then
      name = names[1]
      self:Select(mapID, name)
    else
      name = self:CreateRoute(mapID, L["My route"])
    end
  end
  local count = self:AddPoint(mapID, name, x, y)
  self:Print(format(L["Point added to %s (%d points)."], name, count or 0))
end

function FW:OptimizeRoute(mapID, name)
  local r = self:GetRoute(mapID, name)
  if not r or #r.points < 4 then return end
  r.points = ns.Optimize.Optimize(r.points, self:GetAspect(mapID))
  self:Fire()
end

function FW:CreateFromSources(mapID, name, selections)
  local points = ns.Sources.CollectPoints(mapID, selections)
  if #points == 0 then return end
  points = ns.Optimize.Optimize(points, self:GetAspect(mapID))
  return self:CreateRoute(mapID, name, points, selections)
end

-- Reprend les ressources choisies à la création : ajoute les nouveaux points
-- découverts depuis par GatherMate2 et recalcule le trajet.
function FW:RefreshFromSources(mapID, name)
  local r = self:GetRoute(mapID, name)
  if not r or not r.sources or not ns.Sources.Available() then return end
  local points = ns.Sources.CollectPoints(mapID, r.sources)
  if #points == 0 then return end
  r.points = ns.Optimize.Optimize(points, self:GetAspect(mapID))
  self:Fire()
  return #points
end

function FW:ExportRoute(mapID, name)
  local r = self:GetRoute(mapID, name)
  if not r then return end
  return ns.Share.Encode(mapID, name, r.color, r.points)
end

local IMPORT_ERRORS = {
  format = "This is not a FarmWay route.",
  version = "This route was made with a newer FarmWay. Update the addon.",
  points = "This route is damaged: copy it again in full.",
}

function FW:ImportRoute(text)
  local data, err = ns.Share.Decode(text)
  if not data then return nil, L[IMPORT_ERRORS[err] or IMPORT_ERRORS.format] end
  local name, r = self:CreateRoute(data.mapID, data.name, data.points)
  r.color = data.color
  r.colorIndex = nil
  self:Fire()
  return data.mapID, name
end

function FW:ZoneName(mapID)
  local info = mapID and C_Map.GetMapInfo(mapID)
  return info and info.name or ("#" .. tostring(mapID))
end

------------------------------------------------------------------------
-- Démarrage et commandes
------------------------------------------------------------------------

FW:RegisterEvent("ADDON_LOADED")
FW:RegisterEvent("PLAYER_LOGIN")
FW:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then
      self:InitDB()
    elseif arg1 == "Blizzard_WorldMap" and #mapReady > 0 then
      local pending = mapReady
      mapReady = {}
      for _, fn in ipairs(pending) do fn() end
    end
  elseif event == "PLAYER_LOGIN" then
    for _, mod in ipairs({ ns.MapDraw, ns.Minimap, ns.UI }) do
      local ok, err = pcall(mod.Init, mod)
      if not ok then geterrorhandler()(err) end
    end
  end
end)

local function toggleSetting(key, label)
  FW.db.settings[key] = not FW.db.settings[key]
  FW:Print(format(L[label], FW.db.settings[key] and L["on"] or L["off"]))
  FW:Fire()
end

SLASH_FARMWAY1 = "/farmway"
SLASH_FARMWAY2 = "/fw"
SlashCmdList.FARMWAY = function(msg)
  local cmd = strlower(strtrim(msg or ""))
  if cmd == "add" or cmd == "ajouter" then
    FW:AddPlayerPosition()
  elseif cmd == "minimap" or cmd == "minicarte" then
    toggleSetting("minimap", "Minimap routes: %s")
  elseif cmd == "map" or cmd == "carte" then
    toggleSetting("worldmap", "World map routes: %s")
  elseif cmd == "help" or cmd == "aide" then
    FW:Print(L["Commands:"])
    FW:Print(L["/fw - open FarmWay on the world map"])
    FW:Print(L["/fw add - add your position to the selected route"])
    FW:Print(L["/fw minimap - show or hide routes on the minimap"])
    FW:Print(L["/fw map - show or hide routes on the world map"])
  else
    ns.UI:Open()
  end
end
