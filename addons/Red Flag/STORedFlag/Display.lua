local _, A = ...
local M=A.Model
local badges,bindings,hooks={},{},{}
local texture="Interface\\AddOns\\STORedFlag\\flag"
local function safeName(name)
    if issecretvalue and issecretvalue(name) then return nil end
    if type(name)=="string" then return A:Name(name) end
end
local function badge(owner,name,option)
    local b=badges[owner]
    if not name or not A.options[option] or not owner:IsShown() or #A:Reports(name)==0 then
        if b then b:Hide() end; return
    end
    if InCombatLockdown() then if b then b:Hide() end; return end
    if not b then
        -- Independent overlay: no scripts, sizes or anchors on protected Blizzard unit buttons are changed.
        b=CreateFrame("Button",nil,UIParent)
        b:SetSize(16,16); b:SetFrameStrata("HIGH")
        b.icon=b:CreateTexture(nil,"ARTWORK"); b.icon:SetAllPoints(); b.icon:SetTexture(texture)
        b:SetScript("OnEnter",function(self) A:Tip(self,self.target) end)
        b:SetScript("OnLeave",function() GameTooltip:Hide() end)
        b:SetScript("OnClick",function(self) A:Open(self.target) end)
        badges[owner]=b
    end
    b.target=name
    b:ClearAllPoints(); b:SetPoint("RIGHT",owner,"LEFT",-2,0); b:Show()
end
function A:RefreshDisplays()
    if not self.options then return end
    if InCombatLockdown() then for _,b in pairs(badges) do b:Hide() end; return end
    local visited={}
    local function unit(owner,option)
        if not owner then return end
        visited[owner]=true
        local token=owner.unit
        if issecretvalue and issecretvalue(token) then token=nil end
        if not token and owner.GetAttribute then token=owner:GetAttribute("unit") end
        if issecretvalue and issecretvalue(token) then token=nil end
        badge(owner,token and self:UnitName(token),option)
    end
    unit(TargetFrame,"target"); unit(FocusFrame,"target")
    for i=1,4 do
        unit(_G["PartyMemberFrame"..i],"group")
        unit(PartyFrame and (PartyFrame["MemberFrame"..i] or (PartyFrame.MemberFrame and PartyFrame.MemberFrame[i])),"group")
    end
    if PartyFrame and PartyFrame.PartyMemberFramePool then
        for owner in PartyFrame.PartyMemberFramePool:EnumerateActive() do unit(owner,"group") end
    end
    if CompactRaidFrameContainer and CompactRaidFrameContainer.memberUnitToUnitFrame then
        for _,owner in pairs(CompactRaidFrameContainer.memberUnitToUnitFrame) do unit(owner,"group") end
    end
    for i=1,40 do unit(_G["CompactRaidFrame"..i],"group") end
    for i=1,5 do unit(_G["CompactPartyFrameMember"..i],"group") end
    for group=1,8 do for member=1,5 do unit(_G["CompactRaidGroup"..group.."Member"..member],"group") end end
    for owner,resolve in pairs(bindings) do
        visited[owner]=true
        local ok,name=pcall(resolve)
        badge(owner,ok and safeName(name),"lfg")
    end
    for owner,b in pairs(badges) do if not visited[owner] then b:Hide() end end
end
function A:InstallHooks()
    local function hook(name,fn)
        if not hooks[name] and type(_G[name])=="function" then hooksecurefunc(name,fn); hooks[name]=true end
    end
    hook("LFGListSearchEntry_Update",function(entry)
        bindings[entry]=function()
            if not entry.resultID or not C_LFGList then return end
            local info=C_LFGList.GetSearchResultInfo(entry.resultID)
            return info and info.leaderName
        end
    end)
    hook("LFGListApplicationViewer_UpdateApplicantMember",function(member,appID,index)
        bindings[member]=function() return C_LFGList.GetApplicantMemberInfo(appID,index) end
    end)
end
function A:InitDisplays()
    self:InstallHooks()
    local elapsed=0
    local f=CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED"); f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent",function() A:RefreshDisplays() end)
    f:SetScript("OnUpdate",function(_,dt)
        elapsed=elapsed+dt
        if elapsed>.5 then elapsed=0; A:RefreshDisplays() end
    end)
    local function filter(_,_,message,author,...)
        if not A.options.chat or (issecretvalue and (issecretvalue(author) or issecretvalue(message))) then return false end
        local name=safeName(author)
        if not name or #A:Reports(name)==0 then return false end
        return false,"|Hplayer:"..name.."|h|T"..texture..":14:14|t|h "..message,author,...
    end
    for _,event in ipairs({"SAY","YELL","PARTY","PARTY_LEADER","RAID","RAID_LEADER","RAID_WARNING","GUILD","OFFICER","WHISPER","CHANNEL","INSTANCE_CHAT","INSTANCE_CHAT_LEADER","EMOTE","TEXT_EMOTE"}) do
        ChatFrame_AddMessageEventFilter("CHAT_MSG_"..event,filter)
    end
    local function chatHook(chat)
        if not chat or chat.storfHook then return end
        chat.storfHook=true
        chat:HookScript("OnHyperlinkEnter",function(self,link)
            if not A.options.chat or type(link)~="string" then return end
            local name=link:match("^player:([^:]+)")
            if name then A:Tip(self,name) end
        end)
        chat:HookScript("OnHyperlinkLeave",function() GameTooltip:Hide() end)
    end
    for i=1,NUM_CHAT_WINDOWS or 10 do chatHook(_G["ChatFrame"..i]) end
    if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow",function()
        for _,name in ipairs(CHAT_FRAMES or {}) do chatHook(_G[name]) end
    end) end
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit,function(tip)
            if not A.options.tooltip or tip~=GameTooltip then return end
            local _,unit=tip:GetUnit()
            local name=unit and A:UnitName(unit)
            if not name then return end
            for _,r in ipairs(A:Reports(name)) do
                tip:AddLine("STO Red Flag : "..r.reason,1,.2,.2,true)
                tip:AddLine(r.author,.65,.65,.65)
            end
        end)
    end
end
