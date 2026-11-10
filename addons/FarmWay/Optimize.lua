-- Calcul du trajet le plus court qui passe par tous les points (boucle fermée).
-- Aucune fonction du jeu ici : ce fichier se teste hors de WoW.
local _, ns = ...

local O = {}
ns.Optimize = O

local sqrt, huge = math.sqrt, math.huge

-- `aspect` = largeur / hauteur réelle de la carte, pour des distances justes.
local function dist(a, b, aspect)
  local dx = (a[1] - b[1]) * aspect
  local dy = a[2] - b[2]
  return sqrt(dx * dx + dy * dy)
end
O.Distance = dist

function O.Length(points, aspect)
  local n = #points
  if n < 2 then return 0 end
  local total = 0
  for i = 1, n do
    total = total + dist(points[i], points[i % n + 1], aspect)
  end
  return total
end

-- Premier jet : on va toujours au point le plus proche, en partant du plus à l'ouest.
local function nearestNeighbor(points, aspect)
  local n = #points
  local start = 1
  for i = 2, n do
    if points[i][1] < points[start][1] then start = i end
  end
  local used = { [start] = true }
  local order = { start }
  local current = start
  for _ = 2, n do
    local best, bestD = nil, huge
    for j = 1, n do
      if not used[j] then
        local d = dist(points[current], points[j], aspect)
        if d < bestD then best, bestD = j, d end
      end
    end
    used[best] = true
    order[#order + 1] = best
    current = best
  end
  return order
end

-- Amélioration « 2-opt » : on décroise les segments tant que le trajet raccourcit.
local function twoOpt(order, points, aspect, maxPasses)
  local n = #order
  if n < 4 then return end
  local cache = {}
  local function d(p, q)
    if p > q then p, q = q, p end
    local key = p * 100000 + q
    local v = cache[key]
    if not v then
      v = dist(points[p], points[q], aspect)
      cache[key] = v
    end
    return v
  end
  for _ = 1, maxPasses do
    local improved = false
    for i = 1, n - 2 do
      local a = order[i]
      local b = order[i + 1]
      local dab = d(a, b)
      for j = i + 2, n do
        if not (i == 1 and j == n) then
          local c, e = order[j], order[j % n + 1]
          if d(a, c) + d(b, e) - dab - d(c, e) < -1e-9 then
            local lo, hi = i + 1, j
            while lo < hi do
              order[lo], order[hi] = order[hi], order[lo]
              lo, hi = lo + 1, hi - 1
            end
            improved = true
            b = order[i + 1]
            dab = d(a, b)
          end
        end
      end
    end
    if not improved then break end
  end
end

-- Renvoie une nouvelle liste de points, dans l'ordre du trajet optimisé.
function O.Optimize(points, aspect, maxPasses)
  aspect = aspect or 1.5
  local n = #points
  local out = {}
  if n < 4 then
    for i = 1, n do out[i] = { points[i][1], points[i][2] } end
    return out
  end
  local order = nearestNeighbor(points, aspect)
  twoOpt(order, points, aspect, maxPasses or (n > 400 and 8 or 40))
  for i, idx in ipairs(order) do
    out[i] = { points[idx][1], points[idx][2] }
  end
  return out
end

-- Insère un point là où il allonge le moins la boucle ; renvoie sa position.
function O.InsertPoint(points, p, aspect)
  aspect = aspect or 1.5
  local n = #points
  if n < 2 then
    points[n + 1] = p
    return n + 1
  end
  local bestI, bestCost = n, huge
  for i = 1, n do
    local a, b = points[i], points[i % n + 1]
    local cost = dist(a, p, aspect) + dist(p, b, aspect) - dist(a, b, aspect)
    if cost < bestCost then bestI, bestCost = i, cost end
  end
  table.insert(points, bestI + 1, p)
  return bestI + 1
end
