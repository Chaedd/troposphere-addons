-- Dessin des routes de la zone actuelle sur la minicarte.
local _, ns = ...
local FW = ns.FW

local MM = {}
ns.Minimap = MM

-- Diamètre visible de la minicarte (en yards) pour chaque niveau de zoom.
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }
local DOT_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local UPDATE_EVERY = 0.05

local frame
local lines, dots = {}, {}
local elapsed = 0

local function acquireLine(i)
  local line = lines[i]
  if not line then
    line = frame:CreateLine(nil, "ARTWORK")
    lines[i] = line
  end
  return line
end

local function acquireDot(i)
  local dot = dots[i]
  if not dot then
    dot = frame:CreateTexture(nil, "OVERLAY")
    dot:SetTexture(DOT_TEXTURE)
    dots[i] = dot
  end
  return dot
end

-- Garde la partie du segment [p, q] qui est dans le cercle de rayon r.
local function clipCircle(x0, y0, x1, y1, r)
  local dx, dy = x1 - x0, y1 - y0
  local a = dx * dx + dy * dy
  if a == 0 then return end
  local b = 2 * (x0 * dx + y0 * dy)
  local c = x0 * x0 + y0 * y0 - r * r
  local disc = b * b - 4 * a * c
  if disc <= 0 then return end
  local s = math.sqrt(disc)
  local t0, t1 = (-b - s) / (2 * a), (-b + s) / (2 * a)
  if t0 < 0 then t0 = 0 end
  if t1 > 1 then t1 = 1 end
  if t0 >= t1 then return end
  return x0 + dx * t0, y0 + dy * t0, x0 + dx * t1, y0 + dy * t1
end

-- Même chose pour une minicarte carrée (demi-côté r).
local function clipSquare(x0, y0, x1, y1, r)
  local dx, dy = x1 - x0, y1 - y0
  local t0, t1 = 0, 1
  local checks = { { -dx, x0 + r }, { dx, r - x0 }, { -dy, y0 + r }, { dy, r - y0 } }
  for _, pq in ipairs(checks) do
    local p, q = pq[1], pq[2]
    if p == 0 then
      if q < 0 then return end
    else
      local t = q / p
      if p < 0 then
        if t > t1 then return end
        if t > t0 then t0 = t end
      else
        if t < t0 then return end
        if t < t1 then t1 = t end
      end
    end
  end
  return x0 + dx * t0, y0 + dy * t0, x0 + dx * t1, y0 + dy * t1
end

function MM:Update()
  local nLines, nDots = 0, 0
  local settings = FW.db.settings
  local mapID, px, py
  if settings.minimap then mapID, px, py = FW:GetPlayerPosition() end
  local zone = mapID and FW.db.routes[mapID]
  local mapW, mapH = FW:GetMapYards(mapID)

  if zone and mapW then
    local zoom = Minimap:GetZoom() or 0
    local diameter = ((IsIndoors and IsIndoors()) and INDOOR or OUTDOOR)[zoom] or OUTDOOR[0]
    local radius = Minimap:GetWidth() / 2
    local scale = radius / (diameter / 2) -- pixels par yard
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    local clip = square and clipSquare or clipCircle

    local cosF, sinF = 1, 0
    if GetCVar("rotateMinimap") == "1" then
      local facing = GetPlayerFacing and GetPlayerFacing()
      if facing then cosF, sinF = math.cos(-facing), math.sin(-facing) end
    end

    local function toPixels(p)
      local ox = (p[1] - px) * mapW * scale
      local oy = -(p[2] - py) * mapH * scale
      return ox * cosF - oy * sinF, ox * sinF + oy * cosF
    end

    local thickness = settings.minimapWidth
    for name, r in pairs(zone) do
      if r.visible then
        local pts = r.points
        local n = #pts
        local cr, cg, cb = r.color[1], r.color[2], r.color[3]
        local alpha = FW:IsSelected(mapID, name) and 1 or 0.8
        local proj = {}
        for i = 1, n do
          local x, y = toPixels(pts[i])
          proj[i] = { x, y }
        end
        local segments = n > 2 and n or (n == 2 and 1 or 0)
        for i = 1, segments do
          local a, b = proj[i], proj[i % n + 1]
          local x0, y0, x1, y1 = clip(a[1], a[2], b[1], b[2], radius - 2)
          if x0 then
            nLines = nLines + 1
            local line = acquireLine(nLines)
            line:SetThickness(thickness)
            line:SetColorTexture(cr, cg, cb, alpha)
            line:SetStartPoint("CENTER", frame, x0, y0)
            line:SetEndPoint("CENTER", frame, x1, y1)
            line:Show()
          end
        end
        for i = 1, n do
          local x, y = proj[i][1], proj[i][2]
          local inside
          if square then
            inside = math.abs(x) < radius - 3 and math.abs(y) < radius - 3
          else
            inside = x * x + y * y < (radius - 3) * (radius - 3)
          end
          if inside then
            nDots = nDots + 1
            local dot = acquireDot(nDots)
            dot:SetSize(thickness + 4, thickness + 4)
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", frame, "CENTER", x, y)
            dot:SetVertexColor(cr, cg, cb, alpha)
            dot:Show()
          end
        end
      end
    end
  end

  for i = nLines + 1, #lines do lines[i]:Hide() end
  for i = nDots + 1, #dots do dots[i]:Hide() end
end

function MM:Init()
  if frame or not Minimap then return end
  frame = CreateFrame("Frame", nil, Minimap)
  frame:SetAllPoints(Minimap)
  frame:SetFrameLevel(Minimap:GetFrameLevel() + 5)
  frame:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < UPDATE_EVERY then return end
    elapsed = 0
    MM:Update()
  end)
  FW:RegisterCallback(function() MM:Update() end)
end
