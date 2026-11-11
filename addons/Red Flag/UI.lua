local _, A = ...
local M=A.Model
local function lastPage(n) return math.max(0,math.floor((n-1)/7)*7) end
local function pretty(name) return name and name:gsub("%-"," ") or "" end
local function panel(parent,x,y,w,h)
    local p=CreateFrame("Frame",nil,parent,"InsetFrameTemplate")
    p:SetSize(w,h); p:SetPoint("TOPLEFT",x,y)
    return p
end
local function text(parent,value,x,y,w,font)
    local s=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlight")
    s:SetPoint("TOPLEFT",x,y); s:SetWidth(w); s:SetJustifyH("LEFT"); s:SetText(value)
    return s
end
local function button(parent,value,x,y,w,action)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(w,32); b:SetPoint("TOPLEFT",x,y)
    b.caption=b:GetFontString(); b:SetText(value)
    b:SetScript("OnClick",action)
    return b
end
local function edit(parent,x,y,w,h,max,multiline)
    local e
    if multiline then
        local bg=CreateFrame("Frame",nil,parent,"BackdropTemplate")
        bg:SetSize(w,h); bg:SetPoint("TOPLEFT",x,y)
        bg:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
        bg:SetBackdropColor(0,0,0,.55); bg:SetBackdropBorderColor(.6,.6,.6,1)
        e=CreateFrame("EditBox",nil,bg)
        e:SetPoint("TOPLEFT",10,-8); e:SetPoint("BOTTOMRIGHT",-10,8)
    else
        e=CreateFrame("EditBox",nil,parent,"InputBoxTemplate")
        e:SetSize(w-16,h-12); e:SetPoint("TOPLEFT",x+8,y-6)
    end
    e:SetFontObject(GameFontHighlight); e:SetAutoFocus(false); e:SetMaxBytes(max)
    if multiline then e:SetMultiLine(true) end
    e:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    return e
end
local function ownReport(name)
    if not name or not A.records or not A.player then return end
    local r=A.records[M.Key(name)..":"..M.Key(A.player)]
    if r and not r.deleted then return r end
end

function A:SetUITab(key)
    local f=self.window
    if not f or not f.pages[key] then return end
    f.tab=key
    f.name:ClearFocus(); f.reason:ClearFocus(); f.search:ClearFocus()
    for name,page in pairs(f.pages) do
        page:SetShown(name==key)
        if name==key then PanelTemplates_SelectTab(f.tabs[name])
        else PanelTemplates_DeselectTab(f.tabs[name]) end
    end
    self:RefreshUI()
end

function A:UpdateReportForm()
    local f=self.window
    if not f then return end
    local name=self:Name(f.name:GetText())
    local reason=M.Plain(f.reason:GetText())
    local own=ownReport(name)
    local valid=self.records~=nil and name~=nil and #reason>0 and #reason<=200
    f.save:SetEnabled(valid)
    f.save:SetText(own and "Enregistrer les modifications" or "Partager le signalement")
    f.formCount:SetText(#f.reason:GetText().." / 200 octets")
    f.formHint:SetText(not self.records and "Rejoins une guilde pour partager un signalement." or
        (not name and "Indique le prénom et le nom de famille, ou utilise ta cible." or
        (#reason==0 and "Décris les faits pour aider les autres membres de la guilde." or
        "Le signalement sera partagé avec ta guilde, sous ton nom.")))
end

function A:RefreshSyncStatus()
    local f=self.window
    if not f or not f:IsShown() then return end
    local s=self.GetSyncDebugState and self:GetSyncDebugState()
    local status="Partage entre membres de guilde"
    if not self.scope then status="Hors guilde : partage désactivé"
    elseif s and s.status=="échange en cours" then status="Synchronisation en cours…"
    elseif s and s.status=="attente de pair" then status="Synchronisation : recherche d'un membre connecté…"
    elseif s and s.status=="demande expirée" then status="Aucun pair trouvé. Un membre équipé doit être connecté."
    elseif self.lastCompleted then status="Dernier échange : "..date("%H:%M",self.lastCompleted) end
    f.syncStatus:SetText(status); f.sync:SetEnabled(self.scope~=nil)
end

function A:CreateUI()
    local f=CreateFrame("Frame","RedFlagWindow",UIParent,"BasicFrameTemplateWithInset")
    self.window=f
    f:SetSize(820,600); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing)
    f.TitleText:SetText("Red Flag — Signalements de guilde")
    f.subtitle=text(f,"Les signalements de ta guilde, au même endroit.",24,-48,710,"GameFontHighlightSmall")
    tinsert(UISpecialFrames,"RedFlagWindow")
    f.pages,f.tabs={},{}
    f.tabPadding,f.minTabWidth,f.maxTabWidth=30,150,200
    for i,item in ipairs({{"list","Signalements",180},{"report","Ajouter / modifier",200},{"settings","Réglages",150}}) do
        local key=item[1]
        f.pages[key]=panel(f,20,-114,780,414)
        local tab=CreateFrame("Button",nil,f,"PanelTopTabButtonTemplate")
        tab:SetSize(item[3],32); tab:SetPoint("TOPLEFT",20+(i-1)*220,-82)
        tab:SetText(item[2]); tab:SetScript("OnClick",function() A:SetUITab(key) end)
        f.tabs[key]=tab
    end
    local p=f.pages.list
    f.search=edit(p,12,-12,280,34,100); f.search:SetText("")
    button(p,"Effacer",300,-12,72,function() f.search:SetText("") end)
    text(p,"RECHERCHER UN JOUEUR",12,-54,350,"GameFontDisableSmall")
    f.rows,f.offset={},0
    for i=1,7 do
        local row=CreateFrame("Button",nil,p)
        row:SetSize(360,32); row:SetPoint("TOPLEFT",12,-78-(i-1)*38)
        row:SetScript("OnClick",function(self) f.selected=self.target; A:RefreshUI() end)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
        row.bg=row:CreateTexture(nil,"BACKGROUND")
        row.bg:SetAllPoints(); row.bg:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight"); row.bg:SetBlendMode("ADD")
        row.text=text(row,"",10,-7,260)
        row.count=text(row,"",285,-8,60,"GameFontHighlightSmall")
        row:SetScript("OnEnter",function(self) if self.target then A:Tip(self,self.target) end end)
        row:SetScript("OnLeave",function() GameTooltip:Hide() end)
        f.rows[i]=row
    end
    f.empty=text(p,"",24,-140,320)
    f.previous=button(p,"Précédent",12,-358,106,function() f.offset=math.max(0,f.offset-7); A:RefreshUI() end)
    f.next=button(p,"Suivant",266,-358,106,function() f.offset=math.min(lastPage(#f.entries),f.offset+7); A:RefreshUI() end)
    f.pageCount=text(p,"",128,-369,130,"GameFontHighlightSmall")
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel",function(_,delta)
        f.offset=math.max(0,math.min(lastPage(#f.entries),f.offset-delta*3)); A:RefreshUI()
    end)
    f.detail=panel(p,388,-12,380,390)
    f.detailName=text(f.detail,"Sélectionne un joueur",16,-16,348,"GameFontNormalLarge")
    f.detailCount=text(f.detail,"",16,-43,348,"GameFontHighlightSmall")
    f.detailScroll=CreateFrame("ScrollFrame",nil,f.detail,"UIPanelScrollFrameTemplate")
    f.detailScroll:SetPoint("TOPLEFT",16,-70); f.detailScroll:SetPoint("BOTTOMRIGHT",-34,94)
    local content=CreateFrame("Frame",nil,f.detailScroll); content:SetSize(320,1)
    f.detailScroll:SetScrollChild(content); f.detailContent=content
    f.detailText=text(content,"",0,0,320)
    f.modify=button(f.detail,"Ajouter mon avis",16,-300,348,function() if f.selected then A:Open(f.selected) end end,true)
    f.remove=button(f.detail,"Retirer mon signalement",16,-342,348,function()
        if f.selected and ownReport(f.selected) then A:SetReport(f.selected,"",true) end
    end)
    f.search:SetScript("OnTextChanged",function() f.offset=0; A:RefreshUI() end)

    p=f.pages.report
    text(p,"Un signalement utile commence par des faits.",24,-20,720,"GameFontNormalLarge")
    text(p,"Joueur",24,-60,400)
    f.name=edit(p,24,-82,500,36,100)
    f.target=button(p,"Utiliser ma cible",540,-82,216,function()
        local name=UnitIsPlayer("target") and A:UnitName("target")
        if name then A:Open(name) else A:Print("Cible un joueur.") end
    end)
    text(p,"Prénom Nomdefamille ou Prénom-Nomdefamille",24,-126,710,"GameFontDisableSmall")
    text(p,"Motif",24,-160,400)
    f.reason=edit(p,24,-184,732,100,200,true)
    f.formCount=text(p,"",580,-294,176,"GameFontHighlightSmall")
    f.formHint=text(p,"",24,-320,732,"GameFontHighlightSmall")
    f.save=button(p,"Partager le signalement",24,-360,330,function()
        local name=A:Name(f.name:GetText())
        if A:SetReport(name,f.reason:GetText(),false) then
            f.selected=name; f.search:SetText("")
            for i,target in ipairs(f.entries) do if target==name then f.offset=math.floor((i-1)/7)*7; break end end
            A:SetUITab("list")
        end
    end,true)
    f.clear=button(p,"Vider le formulaire",370,-360,230,function() f.name:SetText(""); f.reason:SetText(""); f.name:SetFocus() end)
    f.name:SetText(""); f.reason:SetText("")
    f.name:SetScript("OnTextChanged",function() A:UpdateReportForm() end)
    f.reason:SetScript("OnTextChanged",function() A:UpdateReportForm() end)
    f.name:SetScript("OnEnterPressed",function(self) self:ClearFocus(); f.reason:SetFocus() end)
    f.name:SetScript("OnTabPressed",function(self) self:ClearFocus(); f.reason:SetFocus() end)
    f.reason:SetScript("OnTabPressed",function(self) self:ClearFocus(); f.name:SetFocus() end)

    p=f.pages.settings
    text(p,"Où afficher les drapeaux ?",24,-20,700,"GameFontNormalLarge")
    text(p,"Ces réglages s'appliquent à ton installation.",24,-50,700,"GameFontHighlightSmall")
    f.checks={}
    local options={
        {"lfg","Recherche de groupe","Joueurs et groupes dans la fenêtre de recherche."},
        {"group","Groupe et raid","Drapeaux sur les cadres de tes coéquipiers."},
        {"target","Cible et focus","Repère un joueur signalé en le ciblant."},
        {"chat","Messages du chat","Un drapeau à côté du nom dans les nouveaux messages."},
        {"tooltip","Infobulles des joueurs","Les motifs au survol d'un joueur."},
    }
    for i,item in ipairs(options) do
        local key=item[1]
        local check=CreateFrame("CheckButton",nil,p,"UICheckButtonTemplate")
        check:SetPoint("TOPLEFT",20,-76-(i-1)*49)
        text(p,item[2],60,-80-(i-1)*49,650)
        text(p,item[3],60,-100-(i-1)*49,650,"GameFontDisableSmall")
        check:SetScript("OnClick",function(self) A.options[key]=not not self:GetChecked(); A:Changed() end)
        f.checks[key]=check
    end
    text(p,"Un souci ? Le diagnostic permet de copier un rapport technique.",24,-337,720,"GameFontHighlightSmall")
    button(p,"Ouvrir le diagnostic",24,-365,240,function() A:OpenDebug() end)
    text(f,"Les signalements sont partagés entre membres connectés.",24,-543,740,"GameFontDisableSmall")
    f.syncStatus=text(f,"",24,-574,575,"GameFontHighlightSmall")
    f.sync=button(f,"Synchroniser",630,-555,166,function() A:RequestSync(true); A:RefreshSyncStatus() end)
    f.tab="list"
    f:SetScript("OnShow",function() A:RefreshUI() end)
    f:SetScript("OnHide",function() f.name:ClearFocus(); f.reason:ClearFocus(); f.search:ClearFocus() end)
    local elapsed=0
    f:SetScript("OnUpdate",function(_,dt) elapsed=elapsed+dt; if elapsed>=1 then elapsed=0; A:RefreshSyncStatus() end end)
    self:SetUITab("list")
end

function A:RefreshUI()
    local f=self.window
    if not f or not f:IsShown() then return end
    local entries,seen={},{}
    local query=M.Key(f.search:GetText()):gsub("%s+","-")
    local total=0
    for _,r in pairs(self.records or {}) do
        local key=M.Key(r.target)
        if not r.deleted and not seen[key] then
            seen[key]=true; total=total+1
            if query=="" or key:find(query,1,true) then entries[#entries+1]=r.target end
        end
    end
    table.sort(entries,function(a,b) return M.Key(a)<M.Key(b) end)
    f.entries=entries; f.offset=math.max(0,math.min(f.offset,lastPage(#entries)))
    local found=false
    for _,name in ipairs(entries) do if name==f.selected then found=true; break end end
    if not found then f.selected=entries[1] end
    for i,row in ipairs(f.rows) do
        row.target=entries[i+f.offset]; row:SetShown(row.target~=nil)
        if row.target then
            row.text:SetText(pretty(row.target)); row.count:SetText(#self:Reports(row.target).." avis")
            row.bg:SetShown(row.target==f.selected)
            if row.target==f.selected then row.text:SetTextColor(1,.82,0)
            else row.text:SetTextColor(1,1,1) end
        end
    end
    f.previous:SetEnabled(f.offset>0); f.next:SetEnabled(f.offset+7<#entries)
    f.subtitle:SetText(self.scope and (total.." joueur(s) signalé(s) · Liste partagée avec ta guilde") or "Rejoins une guilde pour accéder aux signalements partagés.")
    f.empty:SetText(not self.records and "Aucune guilde\n\nLa liste sera disponible une fois en guilde." or
        (#entries==0 and (query~="" and "Aucun résultat\n\nEssaie une autre recherche." or "Aucun signalement\n\nUtilise l'onglet Ajouter / modifier ou le clic droit sur un joueur.") or ""))
    f.pageCount:SetText(#entries==0 and "0 résultat" or ((f.offset+1).."–"..math.min(f.offset+7,#entries).." / "..#entries))
    local reports=f.selected and self:Reports(f.selected) or {}
    f.detailName:SetText(f.selected and pretty(f.selected) or "Sélectionne un joueur")
    f.detailCount:SetText(f.selected and (#reports.." signalement(s) de la guilde") or "Les motifs et leurs auteurs apparaîtront ici.")
    local lines={}
    for _,r in ipairs(reports) do
        lines[#lines+1]="|cffffd100"..pretty(r.author)..(self.player and M.Key(r.author)==M.Key(self.player) and " (toi)" or "").."|r"
        lines[#lines+1]="|cff9ca6b8"..date("%d/%m/%Y",r.rev).."|r"
        lines[#lines+1]=r.reason.."\n"
    end
    f.detailText:SetText(table.concat(lines,"\n"))
    f.detailContent:SetHeight(math.max(1,f.detailText:GetStringHeight()+8))
    if f.detailKey~=f.selected then f.detailScroll:SetVerticalScroll(0); f.detailKey=f.selected end
    local own=ownReport(f.selected)
    f.modify:SetEnabled(f.selected~=nil and self.records~=nil)
    f.modify:SetText(own and "Modifier mon signalement" or "Ajouter mon avis")
    f.remove:SetEnabled(own~=nil)
    for key,check in pairs(f.checks) do check:SetChecked(self.options[key]) end
    self:UpdateReportForm(); self:RefreshSyncStatus()
end

function A:Open(name)
    if not self.window then self:CreateUI() end
    local f=self.window
    f:Show()
    if name then
        name=self:Name(name)
        if not name then return end
        local own=ownReport(name)
        f.name:SetText(pretty(name)); f.reason:SetText(own and own.reason or "")
        self:SetUITab("report"); f.reason:SetFocus()
    else self:SetUITab("list") end
end

SLASH_REDFLAG1="/redflag"
SLASH_REDFLAG2="/rf"
SlashCmdList.REDFLAG=function(input)
    local cmd,rest=input:match("^(%S+)%s*(.-)$")
    if cmd=="debug" then
        if rest=="on" then A:SetDebug(true)
        elseif rest=="off" then A:SetDebug(false)
        elseif rest=="clear" then A:ClearDebug() end
        A:OpenDebug()
    elseif cmd=="sync" then A:RequestSync(true)
    elseif cmd=="target" or cmd=="cible" then
        local name=UnitIsPlayer("target") and A:UnitName("target")
        if name then A:Open(name) else A:Print("Cible un joueur.") end
    elseif cmd=="add" then
        local name,reason=rest:match("^(%S+)%s+(.+)$")
        if name then A:SetReport(name,reason,false) else A:Print("/redflag add Prénom-Nomdefamille motif") end
    elseif cmd=="remove" then A:SetReport(rest,"",true)
    else A:Open() end
end
