local _, A = ...
RedFlag = A
A.version = "0.1.4"
A.defaults = {group=true, target=true, lfg=true, chat=true, tooltip=true, debug=false}
local M = A.Model
function A:Print(s) DEFAULT_CHAT_FRAME:AddMessage("|cffff4545Red Flag|r : " .. s) end
function A:Realm() return GetNormalizedRealmName() or GetRealmName():gsub("%s", "") end
function A:Name(s) return M.CharacterName(s) end
function A:UnitName(unit)
    local ok, name, surname = pcall(UnitFullName, unit)
    if not ok or (issecretvalue and (issecretvalue(name) or issecretvalue(surname))) or not name then return nil end
    if name:find("[ %-]") then return self:Name(name) end
    if not surname or surname == "" then return nil end
    return self:Name(name .. "-" .. surname)
end
function A:RefreshGuild()
    local guild = GetGuildInfo("player")
    local scope = guild and (self:Realm() .. ":" .. (UnitFactionGroup("player") or "") .. ":" .. guild)
    if scope ~= self.scope then
        self.scope, self.records, self.members = scope, nil, {}
        if self.ResetSync then self:ResetSync() end
        if scope then
            RedFlagDB.guilds[scope] = RedFlagDB.guilds[scope] or {records={}}
            self.records = RedFlagDB.guilds[scope].records
        end
        self:Changed()
    end
    local members = {}
    local total, accepted = 0, 0
    if scope then
        total = GetNumGuildMembers()
        for i=1,total do
            local name = GetGuildRosterInfo(i)
            name = self:Name(name)
            if name then members[M.Key(name)] = true; accepted=accepted+1 end
        end
        if self.player then members[M.Key(self.player)] = true end
    end
    self.members = members
    self.rosterTotal, self.rosterAccepted = total, accepted
    if self.DebugLog then self:DebugLog("ROSTER", "lignes="..total.." noms acceptés="..accepted) end
end
function A:Changed()
    if self.RefreshUI then self:RefreshUI() end
    if self.RefreshDisplays then self:RefreshDisplays() end
end
function A:Reports(name)
    return M.Reports(self.records, self:Name(name))
end
function A:SetReport(name, reason, deleted)
    if not self.records then self:Print("Tu dois être dans une guilde."); return end
    name, reason = self:Name(name), M.Plain(reason)
    if not name then self:Print("Nom invalide. Utilise Prénom-Nomdefamille ou cible le joueur."); return end
    if not deleted and (#reason == 0 or #reason > 200) then self:Print("Le motif est obligatoire (200 octets maximum)."); return end
    local r = {target=name,author=self.player,reason=deleted and "" or reason,deleted=not not deleted,rev=1}
    local old = self.records[M.ID(r)]
    if deleted and (not old or old.deleted) then self:Print("Tu n'as aucun signalement actif pour ce joueur."); return end
    r.rev = math.max(GetServerTime(), old and old.rev+1 or 1)
    if M.Merge(self.records,r) then
        self:Broadcast(r)
        self:Changed()
        self:Print(deleted and "Ton signalement a été retiré." or "Signalement enregistré et mis en partage.")
    else self:Print("Enregistrement refusé : capacité de stockage atteinte.") end
end
function A:Tip(owner, name)
    local reports = self:Reports(name)
    if #reports == 0 then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Red Flag — " .. M.Plain(name),1,.2,.2)
    for _,r in ipairs(reports) do
        GameTooltip:AddLine(r.reason,1,1,1,true)
        GameTooltip:AddLine(r.author .. " — " .. date("%d/%m/%Y",r.rev),.65,.65,.65)
    end
    GameTooltip:Show()
end
local frame = CreateFrame("Frame")
A.events = frame
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
    if A.DebugLog then A:DebugLog("EVENT", event) end
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "Red Flag" then
            RedFlagDB = RedFlagDB or {}
            RedFlagDB.guilds = RedFlagDB.guilds or {}
            RedFlagDB.options = RedFlagDB.options or {}
            A.options = RedFlagDB.options
            for k,v in pairs(A.defaults) do if A.options[k] == nil then A.options[k] = v end end
            frame:RegisterEvent("PLAYER_LOGIN")
            frame:RegisterEvent("PLAYER_GUILD_UPDATE")
            frame:RegisterEvent("GUILD_ROSTER_UPDATE")
        end
        if A.InstallHooks then A:InstallHooks() end
    elseif event == "PLAYER_LOGIN" then
        A.player = A:UnitName("player")
        A:RefreshGuild()
        A:InitSync()
        A:InitDisplays()
        A:InitMinimap()
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        A:Print("v" .. A.version .. " chargé. /redflag pour ouvrir la liste.")
    elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
        A:RefreshGuild()
    end
end)
