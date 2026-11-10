-- Dessin des routes sur la carte du monde, et ajout de points au clic en mode édition.
local _, ns = ...
local FW, L = ns.FW, ns.L

local M = {}
ns.MapDraw = M

local DOT_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local LEVEL_NAME = "PIN_FRAME_LEVEL_FARMWAY"
local lines, dots = {}, {}
local frame, levels

-- Le terrain de la carte est dessiné sur des niveaux de calque gérés par la carte.
-- On demande le nôtre juste au-dessus du surlignage des zones, sous les icônes.
local function setupLevel()
  levels = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
  if levels and levels.InsertFrameLevelAbove then
    local ok = pcall(levels.InsertFrameLevelAbove, levels, LEVEL_NAME, "PIN_FRAME_LEVEL_MAP_HIGHLIGHT", 1)
    if not ok then levels = nil end
  else
    levels = nil
  end
end

local function updateLevel(canvas)
  local level
  if levels then
    local ok, value = pcall(levels.GetValidFrameLevel, levels, LEVEL_NAME)
    if ok and value then level = value end
  end
  -- Sans gestionnaire de niveaux : assez haut pour passer au-dessus du terrain.
  frame:SetFrameLevel(level or (canvas:GetFrameLevel() + 500))
end

local function acquireLine(i)
  local line = lines[i]
  if not line then
    line = frame:CreateLine(nil, "ARTWORK")
    lines[i] = line
  end
  return line
end

local function dotOnClick(self)
  if FW.editing and FW:IsSelected(self.mapID, self.routeName) then
    FW:RemovePoint(self.mapID, self.routeName, self.index)
  end
end

local function dotOnEnter(self)
  if not (FW.editing and FW:IsSelected(self.mapID, self.routeName)) then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(format(L["Point %d of %s"], self.index, self.routeName))
  GameTooltip:AddLine(L["Right-click: remove this point"], 1, 1, 1)
  GameTooltip:Show()
end

local function acquireDot(i)
  local dot = dots[i]
  if not dot then
    dot = CreateFrame("Button", nil, frame)
    dot.tex = dot:CreateTexture(nil, "OVERLAY")
    dot.tex:SetAllPoints()
    dot.tex:SetTexture(DOT_TEXTURE)
    dot:RegisterForClicks("RightButtonUp")
    dot:SetScript("OnClick", dotOnClick)
    dot:SetScript("OnEnter", dotOnEnter)
    dot:SetScript("OnLeave", GameTooltip_Hide)
    dots[i] = dot
  end
  return dot
end

function M:Refresh()
  if not frame then return end
  updateLevel(frame:GetParent())
  local nLines, nDots = 0, 0
  local mapID = WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
  local w, h = frame:GetSize()
  local zone = mapID and FW.db.settings.worldmap and FW.db.routes[mapID]

  if zone and w and w > 0 then
    -- Épaisseur proportionnelle à la taille de la carte, pour rester lisible.
    local unit = w / 1000
    local baseWidth = FW.db.settings.mapWidth * unit
    for name, r in pairs(zone) do
      local selected = FW:IsSelected(mapID, name)
      if r.visible or selected then
        local pts = r.points
        local n = #pts
        local cr, cg, cb = r.color[1], r.color[2], r.color[3]
        local segments = n > 2 and n or (n == 2 and 1 or 0)
        for i = 1, segments do
          local a, b = pts[i], pts[i % n + 1]
          nLines = nLines + 1
          local line = acquireLine(nLines)
          line:SetThickness(selected and baseWidth * 1.6 or baseWidth)
          line:SetColorTexture(cr, cg, cb, selected and 1 or 0.85)
          line:SetStartPoint("TOPLEFT", frame, a[1] * w, -a[2] * h)
          line:SetEndPoint("TOPLEFT", frame, b[1] * w, -b[2] * h)
          line:Show()
        end
        local editable = (selected and FW.editing) and true or false
        local size = (editable and 14 or (selected and 9 or 6)) * unit
        for i = 1, n do
          nDots = nDots + 1
          local dot = acquireDot(nDots)
          dot.mapID, dot.routeName, dot.index = mapID, name, i
          dot:SetSize(size, size)
          dot:ClearAllPoints()
          dot:SetPoint("CENTER", frame, "TOPLEFT", pts[i][1] * w, -pts[i][2] * h)
          dot.tex:SetVertexColor(cr, cg, cb, 1)
          dot:EnableMouse(editable)
          dot:Show()
        end
      end
    end
  end

  for i = nLines + 1, #lines do lines[i]:Hide() end
  for i = nDots + 1, #dots do dots[i]:Hide() end
end

-- En mode édition, un clic simple (pas un glisser) sur la carte ajoute un point.
local function hookClicks(scroll)
  local downX, downY
  scroll:HookScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
      downX, downY = GetCursorPosition()
    end
  end)
  scroll:HookScript("OnMouseUp", function(_, button)
    if button ~= "LeftButton" or not FW.editing or not downX then return end
    local x, y = GetCursorPosition()
    local moved = math.abs(x - downX) + math.abs(y - downY)
    downX, downY = nil, nil
    if moved > 6 then return end
    local mapID, name = FW:GetSelected()
    if not mapID or mapID ~= WorldMapFrame:GetMapID() then return end
    local cx, cy = WorldMapFrame:GetNormalizedCursorPosition()
    if cx and cy and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
      FW:AddPoint(mapID, name, cx, cy)
    end
  end)
end

function M:Init()
  FW:OnWorldMapReady(function()
    if frame then return end
    local scroll = WorldMapFrame.ScrollContainer
    local canvas = scroll.Child or scroll
    frame = CreateFrame("Frame", nil, canvas)
    frame:SetAllPoints(canvas)
    setupLevel()
    updateLevel(canvas)
    frame:SetScript("OnSizeChanged", function() M:Refresh() end)

    WorldMapFrame:HookScript("OnShow", function() M:Refresh() end)
    if WorldMapFrame.OnMapChanged then
      hooksecurefunc(WorldMapFrame, "OnMapChanged", function() M:Refresh() end)
    end
    hookClicks(scroll)
    FW:RegisterCallback(function() M:Refresh() end)
    M:Refresh()
  end)
end
