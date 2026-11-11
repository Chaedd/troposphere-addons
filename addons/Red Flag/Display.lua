local _, A = ...
local M=A.Model
local badges,bindings,hooks={},{},{}
local texture="Interface\\AddOns\\Red Flag\\flag"
local namePrefix="|T"..texture..":16:16|t "
local function restoreName(b)
    if not b or not b.nameLabel then return end
    local text=b.nameLabel:GetText()
    -- A native row update may already have replaced the decorated name.
    if type(text)=="string" and text:sub(1,#namePrefix)==namePrefix then
        b.nameLabel:SetText(text:sub(#namePrefix+1))
        b.nameLabel:SetWidth(b.nameWidth)
    end
    if b.nameOwner and b.nameOwner.OriginalName==b.originalName then b.nameOwner.OriginalName=nil end
    b.nameOwner,b.originalName=nil,nil
    b.nameLabel,b.nameWidth=nil,nil
end
function A:GetDisplayDebugState()
    local state={badges=0,visible=0,bindings=0}
    for _,b in pairs(badges) do state.badges=state.badges+1; if b:IsShown() then state.visible=state.visible+1 end end
    for _ in pairs(bindings) do state.bindings=state.bindings+1 end
    for _,name in ipairs({"LFGListSearchEntry_Update","LFGListApplicationViewer_UpdateApplicantMember","LFGBrowseSearchEntry_Update"}) do state[name]=hooks[name] or false end
    state.foreverBrowse=LFGBrowseFrame and LFGBrowseFrame.ScrollBox~=nil or false
    state.foreverWho=LFGWhoListFrame and LFGWhoListFrame.ScrollBox~=nil or false
    return state
end
local function safeName(name)
    if issecretvalue and issecretvalue(name) then return nil end
    if type(name)=="string" then return A:Name(name) end
end
local function badge(owner,name,option,targets)
    local b=badges[owner]
    restoreName(b)
    if not name or not A.options[option] or not owner:IsShown() or #A:Reports(name)==0 then
        if b then b:Hide() end; return
    end
    if InCombatLockdown() then if b then b:Hide() end; return end
    if not b then
        -- Unit frames keep an independent overlay; native LFG names reserve icon space.
        b=CreateFrame("Button",nil,option=="lfg" and owner or UIParent)
        b:SetSize(16,16)
        b.icon=b:CreateTexture(nil,"ARTWORK"); b.icon:SetAllPoints(); b.icon:SetTexture(texture)
        b:SetScript("OnEnter",function(self)
            if not self.targets or #self.targets<=1 then A:Tip(self,self.target); return end
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            GameTooltip:AddLine("Red Flag — membres signalés",1,.2,.2)
            for _,target in ipairs(self.targets) do
                GameTooltip:AddLine(target,1,.2,.2)
                for _,r in ipairs(A:Reports(target)) do
                    GameTooltip:AddLine(r.reason,1,1,1,true)
                    GameTooltip:AddLine(r.author,.65,.65,.65)
                end
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave",function() GameTooltip:Hide() end)
        b:SetScript("OnClick",function(self) A:Open(self.target) end)
        badges[owner]=b
    end
    -- Follow the owner's stacking order without changing protected unit frames.
    b:SetFrameStrata(owner:GetFrameStrata())
    b:SetFrameLevel(owner:GetFrameLevel()+1)
    b.target,b.targets=name,targets
    b:ClearAllPoints()
    b.icon:Show()
    if option=="lfg" and owner.Name and owner.Name.GetText then
        local label=owner.Name
        local text=label:GetText()
        if type(text)=="string" and not (issecretvalue and issecretvalue(text)) then
            b.nameLabel,b.nameWidth=label,label:GetWidth()
            -- Who-row context menus read OriginalName or the displayed text.
            if not owner.resultID and owner.GetElementData and not owner.OriginalName then
                b.nameOwner,b.originalName=owner,text
                owner.OriginalName=text
            end
            label:SetText(namePrefix..text)
            local limit=owner.NameMaxWidth or b.nameWidth
            if owner.DiscordIcon and owner.DiscordIcon:IsShown() then limit=limit-owner.DiscordIcon:GetWidth()-4 end
            if owner.NewPlayerFriendlyIcon and owner.NewPlayerFriendlyIcon:IsShown() then limit=limit-owner.NewPlayerFriendlyIcon:GetWidth()-1 end
            label:SetWidth(math.min(b.nameWidth+20,math.max(20,limit)))
            b.icon:Hide() -- The inline texture draws the icon; this button handles hover/click.
            b:SetPoint("LEFT",label,"LEFT",0,0)
        else b:SetPoint("TOPRIGHT",owner,"TOPRIGHT",-6,-2) end
    elseif option=="lfg" then b:SetPoint("TOPRIGHT",owner,"TOPRIGHT",-6,-2)
    else b:SetPoint("RIGHT",owner,"LEFT",-2,0) end
    b:Show()
end
local function searchNames(entry)
    if not entry.resultID or not C_LFGList then return end
    local info=C_LFGList.GetSearchResultInfo(entry.resultID)
    if not info or info.isDelisted then return end
    local names={info.leaderName}
    if C_LFGList.GetSearchResultPlayerInfo then
        for i=1,math.min(info.numMembers or 0,40) do
            local member=C_LFGList.GetSearchResultPlayerInfo(entry.resultID,i)
            if member and member.name then names[#names+1]=member.name end
        end
    end
    return names
end
local function bindSearch(entry)
    bindings[entry]=function() return searchNames(entry) end
end
local function scanForeverRows()
    -- Also discover rows created before our hooks and reread recycled rows.
    local browse=LFGBrowseFrame and LFGBrowseFrame.ScrollBox
    if browse and browse.ForEachFrame then
        browse:ForEachFrame(function(entry) if entry.resultID then bindSearch(entry) end end)
    end
    local who=LFGWhoListFrame and LFGWhoListFrame.ScrollBox
    if who and who.ForEachFrame then
        who:ForEachFrame(function(entry)
            bindings[entry]=function()
                local data=entry:GetElementData()
                return data and data.info and data.info.fullName
            end
        end)
    end
end
function A:RefreshDisplays()
    if not self.options then return end
    if InCombatLockdown() then for _,b in pairs(badges) do restoreName(b); b:Hide() end; return end
    scanForeverRows()
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
        local ok,value=pcall(resolve)
        local targets,seen={},{}
        if ok then
            if type(value)~="table" then value={value} end
            for _,raw in ipairs(value) do
                local name=safeName(raw)
                if name and not seen[M.Key(name)] and #self:Reports(name)>0 then
                    seen[M.Key(name)]=true; targets[#targets+1]=name
                end
            end
        end
        badge(owner,targets[1],"lfg",targets)
    end
    for owner,b in pairs(badges) do if not visited[owner] then restoreName(b); b:Hide() end end
end
function A:InstallHooks()
    if self.InstallReportMenus then self:InstallReportMenus() end
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
    hook("LFGBrowseSearchEntry_Update",function(entry)
        bindSearch(entry)
        A:RefreshDisplays()
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
        if not chat or chat.redFlagHook then return end
        chat.redFlagHook=true
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
                tip:AddLine("Red Flag : "..r.reason,1,.2,.2,true)
                tip:AddLine(r.author,.65,.65,.65)
            end
        end)
    end
end
