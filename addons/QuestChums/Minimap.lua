-- QuestChums : bouton de la minicarte (clic : fenêtre ; glisser : le déplacer).
local _, ns = ...

local ICON = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"

function ns:InitMinimap()
  if self.minimapButton or not Minimap then return end
  local b = CreateFrame("Button", "QuestChumsMinimapButton", Minimap)
  self.minimapButton = b
  b:SetSize(32, 32)
  b:SetFrameLevel(Minimap:GetFrameLevel() + 5)
  b:RegisterForClicks("LeftButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local background = b:CreateTexture(nil, "BACKGROUND")
  background:SetSize(24, 24); background:SetPoint("CENTER")
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20); icon:SetPoint("CENTER")
  icon:SetTexture(ICON); icon:SetTexCoord(.08, .92, .08, .92)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(54, 54); border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  local function position()
    local angle = math.rad(tonumber(ns.options.minimapAngle) or 200)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER",
      (Minimap:GetWidth() / 2 + 8) * math.cos(angle),
      (Minimap:GetHeight() / 2 + 8) * math.sin(angle))
  end
  b:SetScript("OnClick", function() ns:Toggle() end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("QuestChums", .4, .8, 1)
    GameTooltip:AddLine("Clic : ouvrir / fermer la fenêtre.", 1, 1, 1)
    GameTooltip:AddLine("Glisser : déplacer autour de la minicarte.", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnDragStart", function(self)
    GameTooltip:Hide()
    self:SetScript("OnUpdate", function()
      local x, y = GetCursorPosition()
      local cx, cy = Minimap:GetCenter()
      if not cx or not cy then return end
      local scale = Minimap:GetEffectiveScale()
      ns.options.minimapAngle = math.deg(math.atan2(y / scale - cy, x / scale - cx))
      position()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  Minimap:HookScript("OnSizeChanged", position)
  position()
end
