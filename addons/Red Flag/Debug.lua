local _, A = ...
local LIMIT=300
local journal,counts,head,total={},{},1,0
local unpack=unpack or table.unpack
local function pack(...) return {n=select("#",...),...} end
local function value(v)
    if issecretvalue and issecretvalue(v) then return "<protégé>" end
    if v==nil then return "<absent>" end
    return tostring(v):gsub("|","/"):gsub("[%z\1-\8\11-\31\127]"," "):sub(1,2000)
end
function A:DebugLog(kind,detail)
    if not self.options or not self.options.debug then return end
    counts[kind]=(counts[kind] or 0)+1
    total=total+1
    journal[head]=string.format("[%.3f] %s %s",GetTime(),value(kind),value(detail))
    head=head%LIMIT+1
end
function A:ClearDebug()
    journal,counts,head,total={},{},1,0
    self:DebugLog("DEBUG","journal effacé")
end
function A:SetDebug(enabled)
    self.options.debug=not not enabled
    self:DebugLog("DEBUG","capture activée")
    self:Print(enabled and "Debug activé. Reproduis le problème puis ouvre /rf debug." or "Debug désactivé. Le journal reste disponible jusqu'au rechargement.")
end
-- Only addon-owned callbacks are wrapped; errors still reach WoW's normal handler.
function A:DebugWrap(name,fn,trace)
    return function(...)
        if not A.options or not A.options.debug then return fn(...) end
        local args=pack(...)
        if trace then A:DebugLog("CALL",name) end
        local result
        local ok,err=xpcall(function() result=pack(fn(unpack(args,1,args.n))) end,function(e)
            local stack=debugstack and debugstack(2,12,0) or "pile indisponible"
            A:DebugLog("ERROR",name..": "..value(e).."\n"..value(stack))
            return e
        end)
        if not ok then error(err,0) end
        return unpack(result,1,result.n)
    end
end
function A:BuildDebugReport()
    local lines={"RED FLAG — RAPPORT TECHNIQUE", "Version addon : "..value(self.version)}
    local function add(k,v) lines[#lines+1]=k.." : "..value(v) end
    local function probe(k,fn)
        local result=pack(pcall(fn))
        if not result[1] then add(k,"indisponible ("..value(result[2])..")"); return end
        local parts={}; for i=2,result.n do parts[#parts+1]=value(result[i]) end
        add(k,table.concat(parts," / "))
    end
    local function section(name,t)
        lines[#lines+1]="\n["..name.."]"
        local keys={}; for k in pairs(t or {}) do keys[#keys+1]=k end
        table.sort(keys)
        for _,k in ipairs(keys) do add(k,t[k]) end
    end
    probe("Date locale",function() return date("%Y-%m-%d %H:%M:%S") end)
    probe("Client / build / date / interface",function() return GetBuildInfo() end)
    probe("Locale",function() return GetLocale() end)
    probe("Temps client (secondes)",function() return GetTime() end)
    probe("Temps serveur",function() return GetServerTime() end)
    probe("FPS",function() return GetFramerate() end)
    probe("Réseau (débit entrant/sortant, latence domicile/monde)",function() return GetNetStats() end)
    probe("Combat",function() return InCombatLockdown() end)
    probe("scriptErrors",function() return GetCVar("scriptErrors") end)
    add("Personnage",self.player); add("Guilde / périmètre",self.scope)
    probe("Cible joueur",function() return UnitIsPlayer("target") and self:UnitName("target") or "aucune" end)
    local members,records,active,deleted,guilds=0,0,0,0,0
    for _ in pairs(self.members or {}) do members=members+1 end
    for _,r in pairs(self.records or {}) do records=records+1; if r.deleted then deleted=deleted+1 else active=active+1 end end
    for _ in pairs(RedFlagDB and RedFlagDB.guilds or {}) do guilds=guilds+1 end
    section("Stockage",{membresConnus=members,guildesLocales=guilds,enregistrements=records,actifs=active,retraits=deleted,limite=self.Model.MAX_RECORDS})
    section("Roster",{lignes=self.rosterTotal or "-",nomsAcceptes=self.rosterAccepted or "-",format="Prénom-Nomdefamille (Forever)"})
    section("Options",self.options)
    local apis={}
    for _,path in ipairs({"C_ChatInfo.RegisterAddonMessagePrefix","C_ChatInfo.SendAddonMessage","C_Timer.After",
        "C_GuildInfo.GuildRoster","C_LFGList.GetSearchResultInfo","C_LFGList.GetApplicantMemberInfo",
        "TooltipDataProcessor.AddTooltipPostCall","UnitFullName","issecretvalue","hooksecurefunc"}) do
        local node=_G
        for key in path:gmatch("[^.]+") do node=type(node)=="table" and node[key] or nil end
        apis[path]=type(node)
    end
    section("API disponibles",apis)
    if self.GetSyncDebugState then section("Synchronisation",self:GetSyncDebugState()) end
    if self.GetDisplayDebugState then section("Affichages",self:GetDisplayDebugState()) end
    section("Interface",{fenetre=self.window and self.window:IsShown() or false,minicarte=self.minimapButton~=nil,
        cible=TargetFrame~=nil,focus=FocusFrame~=nil,groupe=PartyFrame~=nil,raid=CompactRaidFrameContainer~=nil})
    section("Compteurs depuis effacement",counts)
    add("Capture activée",self.options and self.options.debug or false)
    add("Entrées produites / conservées",total.." / "..math.min(total,LIMIT))
    lines[#lines+1]="\n[JOURNAL — ordre chronologique, temps client en secondes]"
    local start=total>=LIMIT and head or 1
    for i=0,math.min(total,LIMIT)-1 do lines[#lines+1]=journal[(start+i-1)%LIMIT+1] end
    lines[#lines+1]="\nFin du rapport. Journal en mémoire uniquement ; noms de personnage/guilde présents. Motifs et contenu des messages exclus."
    return table.concat(lines,"\n")
end
function A:OpenDebug()
    if not self.debugWindow then
        local f=CreateFrame("Frame","RedFlagDebugWindow",UIParent,"BasicFrameTemplateWithInset")
        self.debugWindow=f
        f:SetSize(760,580); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing)
        f.TitleText:SetText("Red Flag : debug et rapport d'exécution")
        tinsert(UISpecialFrames,"RedFlagDebugWindow")
        local caption=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        caption:SetPoint("TOPLEFT",16,-35); caption:SetText("Reproduire le problème, actualiser, cliquer dans le rapport : Ctrl+A puis Ctrl+C. Noms inclus.")
        local check=CreateFrame("CheckButton",nil,f,"UICheckButtonTemplate")
        f.capture=check; check:SetPoint("TOPLEFT",12,-53)
        local text=check:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        text:SetPoint("LEFT",check,"RIGHT",0,0); text:SetText("Capturer le debug")
        check:SetScript("OnClick",function(c) A:SetDebug(c:GetChecked()); A:OpenDebug() end)
        local function button(text,x,fn)
            local b=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
            b:SetSize(135,24); b:SetPoint("TOPLEFT",x,-57); b:SetText(text); b:SetScript("OnClick",fn)
        end
        button("Actualiser",265,function() A:OpenDebug() end)
        button("Tout sélectionner",410,function() f.report:SetFocus(); f.report:HighlightText() end)
        button("Effacer le journal",555,function() A:ClearDebug(); A:OpenDebug() end)
        local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",18,-94); scroll:SetPoint("BOTTOMRIGHT",-34,18)
        local e=CreateFrame("EditBox",nil,scroll)
        f.report=e; f.scroll=scroll
        e:SetMultiLine(true); e:SetFontObject(ChatFontNormal); e:SetWidth(690); e:SetHeight(430)
        e:SetAutoFocus(false); e:SetMaxLetters(0)
        e:SetScript("OnEscapePressed",function(box) box:ClearFocus(); f:Hide() end)
        e:SetScript("OnCursorChanged",function(_,_,y,_,height)
            local top=scroll:GetVerticalScroll(); local bottom=-y+height
            if -y<top then scroll:SetVerticalScroll(-y)
            elseif bottom>top+scroll:GetHeight() then scroll:SetVerticalScroll(bottom-scroll:GetHeight()) end
        end)
        scroll:SetScrollChild(e)
    end
    local f=self.debugWindow
    f.capture:SetChecked(self.options.debug)
    f.report:SetText(self:BuildDebugReport()); f.report:SetCursorPosition(0); f.scroll:SetVerticalScroll(0)
    f:Show(); f.report:SetFocus(); f.report:HighlightText()
end
for _,name in ipairs({"RefreshGuild","SetReport","RequestSync","ResetSync","InitSync","InitDisplays","InitMinimap","Open"}) do
    A[name]=A:DebugWrap(name,A[name],true)
end
for _,name in ipairs({"Receive","RefreshDisplays","RefreshUI","InstallHooks","CreateUI"}) do
    A[name]=A:DebugWrap(name,A[name])
end
local printMessage=A.Print
function A:Print(message)
    self:DebugLog("MESSAGE",message)
    return printMessage(self,message)
end
