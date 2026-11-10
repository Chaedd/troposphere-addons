local _, A = ...
local M = A.Model
local function label(parent,text,x,y)
    local s=parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    s:SetPoint("TOPLEFT",x,y); s:SetText(text)
    return s
end
local function button(parent,text,x,y,width,action)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(width,24); b:SetPoint("TOPLEFT",x,y); b:SetText(text); b:SetScript("OnClick",action)
    return b
end
local function edit(parent,x,y,width,max)
    local e=CreateFrame("EditBox",nil,parent,"InputBoxTemplate")
    e:SetSize(width,24); e:SetPoint("TOPLEFT",x,y); e:SetAutoFocus(false); e:SetMaxBytes(max)
    e:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    return e
end
function A:CreateUI()
    local f=CreateFrame("Frame","RedFlagWindow",UIParent,"BasicFrameTemplateWithInset")
    self.window=f
    f:SetSize(660,615); f:SetPoint("CENTER"); f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing)
    f.TitleText:SetText("Red Flag : signalements de guilde")
    tinsert(UISpecialFrames,"RedFlagWindow")
    label(f,"Joueur (Nom-Royaume si nécessaire)",20,-40)
    f.name=edit(f,25,-62,370,100)
    button(f,"Utiliser ma cible",415,-62,215,function()
        local name=UnitIsPlayer("target") and A:UnitName("target")
        if name then f.name:SetText(name) else A:Print("Cible un joueur.") end
    end)
    label(f,"Motif factuel (200 octets maximum)",20,-96)
    f.reason=edit(f,25,-118,600,200)
    button(f,"Signaler / modifier",20,-151,190,function()
        A:SetReport(f.name:GetText(),f.reason:GetText(),false)
        f.name:ClearFocus(); f.reason:ClearFocus()
    end)
    button(f,"Retirer mon signalement",220,-151,220,function() A:SetReport(f.name:GetText(),"",true) end)
    button(f,"Synchroniser",450,-151,180,function() A:RequestSync(true) end)
    label(f,"Rechercher",20,-194)
    f.search=edit(f,130,-188,495,100)
    f.search:SetScript("OnTextChanged",function() f.offset=0; A:RefreshUI() end)
    f.rows={}; f.offset=0
    for i=1,10 do
        local row=CreateFrame("Button",nil,f)
        row:SetSize(610,24); row:SetPoint("TOPLEFT",20,-222-(i-1)*25)
        row.text=label(row,"",4,-4); row.text:SetWidth(600); row.text:SetJustifyH("LEFT")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row:SetScript("OnEnter",function(self) if self.target then A:Tip(self,self.target) end end)
        row:SetScript("OnLeave",function() GameTooltip:Hide() end)
        row:SetScript("OnClick",function(self)
            f.name:SetText(self.target)
            local own=A.records[M.Key(self.target)..":"..M.Key(A.player)]
            f.reason:SetText(own and not own.deleted and own.reason or "")
        end)
        f.rows[i]=row
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel",function(_,delta)
        f.offset=math.max(0,math.min(math.max(0,#(f.entries or {})-10),f.offset-delta*3)); A:RefreshUI()
    end)
    f.status=label(f,"",20,-480); f.status:SetWidth(610); f.status:SetJustifyH("LEFT")
    label(f,"Afficher les drapeaux :",20,-513)
    local options={{"group","Groupe / raid"},{"target","Cible / focus"},{"lfg","Recherche de groupe"},{"chat","Chat"},{"tooltip","Infobulle joueur"}}
    for i,item in ipairs(options) do
        local check=CreateFrame("CheckButton",nil,f,"UICheckButtonTemplate")
        local key=item[1]
        check:SetPoint("TOPLEFT",20+((i-1)%3)*207,-533-math.floor((i-1)/3)*30)
        local caption=check:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        caption:SetPoint("LEFT",check,"RIGHT",0,0); caption:SetText(item[2])
        check:SetChecked(A.options[key])
        check:SetScript("OnClick",function(self) A.options[key]=self:GetChecked(); A:Changed() end)
    end
    f:SetScript("OnShow",function() A:RefreshUI() end)
end
function A:RefreshUI()
    local f=self.window
    if not f or not f:IsShown() then return end
    local entries,seen={},{}
    local query=M.Key(f.search:GetText())
    for _,r in pairs(self.records or {}) do
        local key=M.Key(r.target)
        if not r.deleted and not seen[key] and (query=="" or key:find(query,1,true)) then
            entries[#entries+1]=r.target; seen[key]=true
        end
    end
    table.sort(entries,function(a,b) return M.Key(a)<M.Key(b) end)
    f.entries=entries; f.offset=math.min(f.offset,math.max(0,#entries-10))
    for i,row in ipairs(f.rows) do
        row.target=entries[i+f.offset]
        if row.target then
            local n=#self:Reports(row.target)
            row.text:SetText("|cffff4545[!] |r"..row.target.."  |cffaaaaaa("..n.." signalement"..(n>1 and "s" or "")..")|r")
            row:Show()
        else row:Hide() end
    end
    f.status:SetText(self.scope and (#entries.." joueur(s) — molette pour défiler. Survol : motifs.\nRetirer efface uniquement ton signalement.") or "Aucune guilde : liste et synchronisation désactivées.")
end
function A:Open(name)
    if not self.window then self:CreateUI() end
    self.window:Show()
    if name then self.window.name:SetText(name); self.window.reason:SetFocus() end
end
SLASH_REDFLAG1="/redflag"
SLASH_REDFLAG2="/rf"
SlashCmdList.REDFLAG=function(input)
    local cmd,rest=input:match("^(%S+)%s*(.-)$")
    if cmd=="sync" then A:RequestSync(true)
    elseif cmd=="target" or cmd=="cible" then
        local name=UnitIsPlayer("target") and A:UnitName("target")
        if name then A:Open(name) else A:Print("Cible un joueur.") end
    elseif cmd=="add" then
        local name,reason=rest:match("^(%S+)%s+(.+)$")
        if name then A:SetReport(name,reason,false) else A:Print("/redflag add Nom-Royaume motif") end
    elseif cmd=="remove" then A:SetReport(rest,"",true)
    else A:Open() end
end
