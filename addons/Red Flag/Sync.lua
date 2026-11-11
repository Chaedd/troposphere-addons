local _, A = ...
local M = A.Model
local PREFIX = "REDFLAG1"
local queue, first, last, serial = {}, 1, 0, 0
local buffers, requests, rates = {}, {}, {}
local offers, transfers = {}, {}
local requestToken, selectedPeer, requestDeadline
function A:GetSyncDebugState()
    local function size(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
    local fragments=0
    for _,bag in pairs(buffers) do fragments=fragments+size(bag) end
    local status=not self.scope and "sans guilde" or (requestDeadline and GetTime()>=requestDeadline and "demande expirée" or
        (selectedPeer and "échange en cours" or (requestToken and "attente de pair" or "repos")))
    return {prefix=PREFIX,status=status,queued=math.max(0,last-first+1),serial=serial,
        buffers=fragments,requests=size(requests),offers=size(offers),transfers=size(transfers),
        requestToken=requestToken or "-",selectedPeer=selectedPeer or "-",deadline=requestDeadline or "-",
        lastRequest=self.lastRequest or "-",lastReceived=self.lastReceived or "-",lastCompleted=self.lastCompleted or "-"}
end
local function enqueue(msg, channel, target)
    if last-first > 30000 then
        if A.DebugLog then A:DebugLog("QUEUE_DROP", "capacité atteinte") end
        return
    end
    last = last+1
    queue[last] = {msg,channel,target}
end
function A:ResetSync()
    queue, first, last = {},1,0
    buffers, requests, rates = {},{},{}
    offers, transfers = {},{}
    requestToken, selectedPeer, requestDeadline = nil,nil,nil
    self.lastRequest = nil
end
function A:SendRecord(r, channel, target)
    serial = serial+1
    local data = M.Pack(r)
    local count = math.ceil(#data/180)
    for i=1,count do
        enqueue("R|" .. serial .. "|" .. i .. "|" .. count .. "|" .. data:sub((i-1)*180+1,i*180),channel,target)
    end
end
function A:Broadcast(r) self:SendRecord(r,"GUILD") end
local function snapshot(peer,token)
    transfers[M.Key(peer)]={token=token,deadline=GetTime()+1800}
    for _,r in pairs(A.records) do A:SendRecord(r,"WHISPER",peer) end
    enqueue("E|"..token,"WHISPER",peer)
end
function A:RequestSync(manual)
    if not self.scope then if manual then self:Print("Tu dois être dans une guilde.") end; return end
    if requestDeadline and GetTime()<requestDeadline then
        if manual then self:Print("Une synchronisation est déjà en cours.") end
        return
    end
    if self.lastRequest and GetTime()-self.lastRequest < 60 then
        if manual then self:Print("Une demande a déjà été envoyée. Réessaie dans une minute.") end
        return
    end
    self.lastRequest = GetTime()
    serial=serial+1
    requestToken=tostring(GetServerTime()).."-"..serial
    selectedPeer=nil
    requestDeadline=GetTime()+15
    enqueue("Q|"..requestToken,"GUILD")
    if manual then self:Print("Synchronisation demandée aux membres connectés.") end
end
function A:Receive(prefix, msg, channel, sender)
    if prefix==PREFIX and self.DebugLog then
        self:DebugLog("RX", tostring(channel).." "..tostring(sender).." "..(type(msg)=="string" and (msg:sub(1,1).." bytes="..#msg) or "invalide"))
    end
    local function reject(reason) if self.DebugLog then self:DebugLog("REJECT",reason) end end
    if prefix ~= PREFIX then return end
    if not self.records or (channel ~= "GUILD" and channel ~= "WHISPER") then reject("sans stockage ou canal incorrect"); return end
    sender = self:Name(sender)
    if sender and M.Key(sender)==M.Key(self.player) then return end
    if not sender or not self.members[M.Key(sender)] then reject("expéditeur absent du roster"); return end
    if type(msg) ~= "string" or #msg > 254 then reject("taille ou type de paquet invalide"); return end
    local now = GetTime()
    local key = M.Key(sender)
    local rate = rates[key]
    if not rate or now-rate.start > 1 then rate={start=now,n=0}; rates[key]=rate end
    rate.n=rate.n+1
    if rate.n > 50 then reject("limite de débit de réception"); return end
    local query=msg:match("^Q|([%d%-]+)$")
    if query and #query<=40 and channel == "GUILD" then
        if requests[key] and now-requests[key] < 60 then return end
        requests[key] = now
        local scope = self.scope
        C_Timer.After(1+math.random()*4,function()
            if A.scope ~= scope or not A.members[key] then return end
            offers[key]={token=query,deadline=GetTime()+20}
            enqueue("O|"..query,"WHISPER",sender)
        end)
        return
    end
    local offer=msg:match("^O|([%d%-]+)$")
    if offer and channel=="WHISPER" then
        if offer==requestToken and not selectedPeer and requestDeadline and now<requestDeadline then
            selectedPeer=key; requestDeadline=now+1800
            enqueue("S|"..offer,"WHISPER",sender)
            snapshot(sender,offer)
        end
        return
    end
    local start=msg:match("^S|([%d%-]+)$")
    if start and channel=="WHISPER" then
        local o=offers[key]
        if o and o.token==start and now<o.deadline then offers[key]=nil; snapshot(sender,start) end
        return
    end
    local finish=msg:match("^E|([%d%-]+)$")
    if finish and channel=="WHISPER" then
        local t=transfers[key]
        if t and t.token==finish then
            transfers[key]=nil
            if selectedPeer==key then requestToken,selectedPeer,requestDeadline=nil,nil,nil end
            self.lastCompleted=GetServerTime()
            if self.DebugLog then self:DebugLog("SYNC_DONE",sender) end
            self:Changed()
        end
        return
    end
    if channel=="WHISPER" and (not transfers[key] or now>transfers[key].deadline) then reject("historique non sollicité ou échange expiré"); return end
    local id, index, count, part = msg:match("^R|(%d+)|(%d+)|(%d+)|(.*)$")
    index,count = tonumber(index),tonumber(count)
    if not id or #id > 12 or count < 1 or count > 12 or index < 1 or index > count or #part > 180 then reject("fragment mal formé"); return end
    local bag = buffers[key]
    if not bag then bag={}; buffers[key]=bag end
    for k,b in pairs(bag) do if now-b.time > 20 then bag[k]=nil end end
    local b = bag[id]
    if not b then
        local n=0; for _ in pairs(bag) do n=n+1 end
        if n >= 8 then reject("trop de réassemblages simultanés"); return end
        b={time=now,count=count,parts={},n=0}; bag[id]=b
    end
    if b.count ~= count then bag[id]=nil; reject("nombre de fragments incohérent"); return end
    if not b.parts[index] then b.n=b.n+1; b.parts[index]=part end
    if b.n == count then
        bag[id]=nil
        local r = M.Unpack(table.concat(b.parts))
        -- Live guild updates must be owned by the actual sender; snapshots trust guild peers.
        if r and r.rev <= GetServerTime()+86400 and (channel == "WHISPER" or M.Key(r.author) == key) then
            if M.Merge(self.records,r) then
                if self.DebugLog then self:DebugLog("MERGE", r.deleted and "retrait accepté" or "signalement accepté") end
                self.lastReceived=GetServerTime(); self:Changed()
            elseif self.DebugLog then self:DebugLog("MERGE", "inchangé ou capacité atteinte") end
        elseif self.DebugLog then self:DebugLog("REJECT", "données invalides, révision future ou auteur différent")
        end
    end
end
function A:InitSync()
    local registered=C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    if self.DebugLog then self:DebugLog("PREFIX", "enregistrement="..tostring(registered)) end
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:SetScript("OnEvent",function(_,_,...) A:Receive(...) end)
    local elapsed, periodic = 0,0
    local function update(_,dt)
        elapsed,periodic=elapsed+dt,periodic+dt
        if elapsed >= .2 then
            elapsed=0
            if A.scope and first<=last then
                local item=queue[first]; queue[first]=nil; first=first+1
                if item[2] == "GUILD" or A.members[M.Key(item[3])] then
                    local target=item[2]=="WHISPER" and M.WhisperTarget(item[3]) or nil
                    local result=C_ChatInfo.SendAddonMessage(PREFIX,item[1],item[2],target)
                    if A.DebugLog then A:DebugLog("TX",item[2].." "..(item[3] or "-").." "..item[1]:sub(1,1).." bytes="..#item[1].." retour="..tostring(result)) end
                end
            end
            if first>last then queue,first,last={},1,0 end
        end
        if periodic>300 then periodic=0; A:RequestSync() end
        if A.scope and not A.lastRequest then A:RequestSync() end
    end
    f:SetScript("OnUpdate",self.DebugWrap and self:DebugWrap("Sync.OnUpdate",update) or update)
end
