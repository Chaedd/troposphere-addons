-- GuildCraft : suivre une recette, comme le bouton « Suivre » de la fenêtre de métier.
-- Le jeu ajoute alors ses composants à la colonne d'objectifs. Si le jeu refuse (fonction
-- absente, recette qu'il ne sait pas suivre), GuildCraft affiche son propre petit suivi :
-- les composants, combien j'en ai et combien il en faut.
local _, ns = ...

local function native() return C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked and C_TradeSkillUI.IsRecipeTracked end

local function nativeTracked(id)
  if not id or not native() then return false end
  local ok, tracked = pcall(C_TradeSkillUI.IsRecipeTracked, id, false)
  return ok and tracked or false
end

function ns:IsTracked(token)
  return self.char.tracked[token] == true or nativeTracked(self:RecipeID(token))
end

function ns:ToggleTrack(token)
  local id = self:RecipeID(token)
  if self:IsTracked(token) then
    if id and native() then pcall(C_TradeSkillUI.SetRecipeTracked, id, false, false) end
    self.char.tracked[token] = nil
  else
    if id and native() then
      pcall(C_TradeSkillUI.SetRecipeTracked, id, true, false)
    end
    if not nativeTracked(id) then
      -- Le jeu ne l'a pas prise : notre propre suivi s'en charge.
      if not self:Reagents(token) then
        self:NeedRecipeData(token)
        self:Print("Composants inconnus pour l'instant : je les demande à la guilde, réessaie dans quelques secondes.")
        return
      end
      self.char.tracked[token] = true
    end
  end
  self:RefreshTracker()
  self:Changed()
end

-- Notre suivi, sous la minicarte.
local GetItemInfoFn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemCountFn = (C_Item and C_Item.GetItemCount) or GetItemCount

local function createTracker()
  local f = CreateFrame("Frame", "GuildCraftTracker", UIParent)
  f:SetSize(240, 40); f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  local pos = ns.options.trackerPos
  if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -60, -260) end
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetRight() - UIParent:GetRight(), self:GetTop() - UIParent:GetTop()
    ns.options.trackerPos = { "TOPRIGHT", x, y }
  end)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT"); f.title:SetText("GuildCraft — Suivi")
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
  f.text:SetWidth(240); f.text:SetJustifyH("LEFT"); f.text:SetSpacing(2)
  f:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then ns:Toggle() end end)
  f:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("GuildCraft — Suivi", .4, .8, 1)
    GameTooltip:AddLine("Glisser : déplacer.", 1, 1, 1)
    GameTooltip:AddLine("Clic droit : ouvrir GuildCraft (bouton « Ne plus suivre »).", 1, 1, 1)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end

function ns:RefreshTracker()
  local lines = {}
  for token in pairs(self.char.tracked) do
    local info = self.RecipeInfo(token)
    lines[#lines + 1] = "|cffffd100" .. info.name .. "|r"
    for _, r in ipairs(self:Reagents(token) or {}) do
      local name = GetItemInfoFn(r.id) or ("Objet n° " .. r.id)
      local have = GetItemCountFn and GetItemCountFn(r.id, true) or 0
      local c = have >= r.n and "ff40ff40" or "ffffffff"
      lines[#lines + 1] = "  |c" .. c .. "- " .. name .. " : " .. math.min(have, r.n) .. "/" .. r.n .. "|r"
    end
  end
  if #lines == 0 then
    if self.tracker then self.tracker:Hide() end
    return
  end
  self.tracker = self.tracker or createTracker()
  self.tracker.text:SetText(table.concat(lines, "\n"))
  self.tracker:SetHeight(20 + self.tracker.text:GetStringHeight())
  self.tracker:Show()
end

function ns:InitTrack()
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "TRACKED_RECIPE_UPDATE" }) do
    pcall(f.RegisterEvent, f, e)
  end
  local pending = false
  f:SetScript("OnEvent", function(_, event)
    if event == "TRACKED_RECIPE_UPDATE" then ns:Changed() end
    if pending then return end
    pending = true
    C_Timer.After(0.5, function() pending = false; ns:RefreshTracker() end)
  end)
  ns:RefreshTracker()
end
