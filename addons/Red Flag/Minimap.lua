local _, A = ...

function A:InitMinimap()
    if self.minimapButton or not Minimap then return end
    local b=CreateFrame("Button","RedFlagMinimapButton",Minimap)
    self.minimapButton=b
    b:SetSize(32,32)
    b:SetFrameLevel(Minimap:GetFrameLevel()+5)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background=b:CreateTexture(nil,"BACKGROUND")
    background:SetSize(24,24); background:SetPoint("CENTER")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon=b:CreateTexture(nil,"ARTWORK")
    icon:SetSize(20,20); icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\AddOns\\Red Flag\\flag")
    local border=b:CreateTexture(nil,"OVERLAY")
    border:SetSize(54,54); border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local function position()
        local angle=math.rad(tonumber(A.options.minimapAngle) or 225)
        b:ClearAllPoints()
        b:SetPoint("CENTER",Minimap,"CENTER",
            (Minimap:GetWidth()/2+8)*math.cos(angle),
            (Minimap:GetHeight()/2+8)*math.sin(angle))
    end
    b:SetScript("OnClick",function()
        if A.window and A.window:IsShown() then A.window:Hide() else A:Open() end
    end)
    b:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_LEFT")
        GameTooltip:AddLine("Red Flag",1,.2,.2)
        GameTooltip:AddLine("Clic : ouvrir / fermer la liste.",1,1,1)
        GameTooltip:AddLine("Glisser : déplacer autour de la minicarte.",1,1,1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave",function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart",function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate",function()
            local x,y=GetCursorPosition()
            local cx,cy=Minimap:GetCenter()
            if not cx or not cy then return end
            local scale=Minimap:GetEffectiveScale()
            A.options.minimapAngle=math.deg(math.atan2(y/scale-cy,x/scale-cx))
            position()
        end)
    end)
    b:SetScript("OnDragStop",function(self) self:SetScript("OnUpdate",nil) end)
    b:SetScript("OnHide",function(self)
        self:SetScript("OnUpdate",nil)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    Minimap:HookScript("OnSizeChanged",position)
    position()
end
