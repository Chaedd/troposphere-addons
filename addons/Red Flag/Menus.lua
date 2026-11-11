local _, A = ...
local M=A.Model
local installed=false
local function readable(value)
    return not (issecretvalue and issecretvalue(value))
end
local function contextName(data)
    if type(data)~="table" then return end
    local unit=data.unit
    if not readable(unit) then return end
    if unit then
        -- Never offer player reporting on NPC/pet portraits, or infer a player
        -- from a partial name when the unit's full name is unavailable.
        local ok,isPlayer=pcall(UnitIsPlayer,unit)
        if not ok or not readable(isPlayer) or not isPlayer then return end
        return A:UnitName(unit)
    end
    if UnitPopupSharedUtil and type(UnitPopupSharedUtil.GetFullPlayerName)=="function" then
        local ok,name=pcall(UnitPopupSharedUtil.GetFullPlayerName,data)
        if ok and readable(name) then
            name=A:Name(name)
            if name then return name end
        end
    end
    local name,surname=data.name,data.surname
    if not readable(name) or not readable(surname) then return end
    local full=A:Name(name)
    if full then return full end
    if type(name)=="string" and type(surname)=="string" and surname~="" then
        return A:Name(name.."-"..surname)
    end
end

function A:OpenReport(name)
    if not self.records then self:Print("Tu dois être dans une guilde."); return end
    name=self:Name(name)
    if not name then return end
    local own=self.player and self.records[M.Key(name)..":"..M.Key(self.player)]
    self:Open(name)
    self.window.reason:SetText(own and not own.deleted and own.reason or "")
    self.window.reason:SetFocus()
end

function A:InstallReportMenus()
    if installed or not Menu or type(Menu.ModifyMenu)~="function" then return end
    local function extend(_,root,data)
        local name=contextName(data)
        if not name then return end
        -- Capture the name now: the target or recycled menu context can change
        -- before the action is clicked.
        local scope=A.scope
        root:CreateDivider()
        local button=root:CreateButton("Signaler avec Red Flag",function()
            if scope~=A.scope then A:Print("La guilde a changé. Rouvre le menu du joueur."); return end
            A:OpenReport(name)
        end)
        button:SetEnabled(A.records~=nil)
    end
    for _,kind in ipairs({"TARGET","FOCUS","PLAYER","ENEMY_PLAYER","PARTY","RAID","RAID_PLAYER",
        "FRIEND","FRIEND_OFFLINE","CHAT_ROSTER","GUILD","GUILD_OFFLINE","COMMUNITIES_WOW_MEMBER",
        "COMMUNITIES_GUILD_MEMBER","RECENT_ALLY","RECENT_ALLY_OFFLINE"}) do
        Menu.ModifyMenu("MENU_UNIT_"..kind,extend)
    end
    installed=true
end
