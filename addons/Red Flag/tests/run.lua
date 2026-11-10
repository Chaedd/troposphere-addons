-- Run from repository root with Lua 5.1+ or .tools/node_modules/.bin/fengari tests/run.lua.
local A={}
assert(loadfile("STORedFlag/Model.lua"))("STORedFlag",A)
local M=A.Model
local passed=0
local function check(value,message) assert(value,message); passed=passed+1 end
local function record(author,reason,rev,deleted,target)
    return {target=target or "Joueur-Hyjal",author=author or "Alice-Hyjal",reason=reason or "Insultes dans le groupe",rev=rev or 100,deleted=not not deleted}
end
check(M.Name("Jou eur","Hyjal")==nil,"Reject spaces in character names")
check(M.Name("Joueur","La Croisade écarlate")=="Joueur-LaCroisadeécarlate","Normalize realm spaces")
check(M.Name("Joueur-Autre","Hyjal")=="Joueur-Autre","Keep explicit realm")
check(M.Name("Joueur-Azjol-Nerub","Hyjal")=="Joueur-Azjol-Nerub","Hyphenated realm supported")
check(M.Name("|Hplayer:X|h","Hyjal")==nil,"Reject markup in names")
check(not M.Valid({rev=1,deleted=false,reason="abc"}),"Missing identity rejected")
check(not M.Valid(record(nil,"",1)),"Empty reason rejected")
check(not M.Valid(record(nil,"Motif |cffffffff",1)),"Markup rejected")
check(not M.Valid(record(nil,"abc",0/0)),"NaN rejected")
check(not M.Valid(record(nil,"abc",1.5)),"Noninteger revision rejected")
local original=record("Élodie-Hyjal","Vol de butin : épée, 100% confirmé.")
local copy=M.Unpack(M.Pack(original))
check(copy and copy.reason==original.reason and copy.author==original.author,"UTF-8 wire round trip")
check(not M.Unpack("bad|packet"),"Malformed payload rejected")
local db={}
check(M.Merge(db,record()),"First report accepted")
check(not M.Merge(db,record()),"Duplicate idempotent")
check(M.Merge(db,record("Bob-Hyjal","Abandon",100)),"Independent author")
check(#M.Reports(db,"joueur-hyjal")==2,"Two authors, case insensitive")
check(#M.Reports(db,"Joueur-Autre")==0,"No cross-realm collision")
check(M.Merge(db,record(nil,"",101,true)),"Deletion accepted")
check(#M.Reports(db,"Joueur-Hyjal")==1,"Deletion preserves other testimony")
check(not M.Merge(db,record(nil,"Old",100)),"Stale snapshot cannot revive deletion")
check(not M.Merge(db,record(nil,"Concurrent",101)),"Deletion wins same revision")
check(M.Merge(db,record(nil,"New",102)),"Explicit later re-add allowed")
local left,right={},{}
M.Merge(left,record(nil,"Alpha",100)); M.Merge(left,record(nil,"Zulu",100))
M.Merge(right,record(nil,"Zulu",100)); M.Merge(right,record(nil,"Alpha",100))
check(M.Pack(left[M.ID(record())])==M.Pack(right[M.ID(record())]),"Concurrent updates converge")
local cap=M.MAX_RECORDS; M.MAX_RECORDS=1
local limited={}; M.Merge(limited,record())
check(not M.Merge(limited,record("Bob-Hyjal")),"Storage capacity bounded")
check(M.Merge(limited,record(nil,"",101,true)),"Deletion allowed at capacity")
M.MAX_RECORDS=cap

-- Multi-client transport simulation: real Sync.lua, delayed timers, throttled queue,
-- peers coming online later, and trusted roster checks. No game client required.
local now,current=0,nil
local clients,timers,bus={},{},{}
GetTime=function() return now end
GetServerTime=function() return 100000+math.floor(now) end
CreateFrame=function()
    local f={}
    function f:RegisterEvent() end
    function f:SetScript(name,fn) self[name]=fn end
    current.frames[#current.frames+1]=f
    return f
end
C_Timer={After=function(delay,fn) timers[#timers+1]={at=now+delay,fn=fn,client=current} end}
C_ChatInfo={RegisterAddonMessagePrefix=function() end,SendAddonMessage=function(prefix,msg,channel,target)
    check(#msg<=254,"Every transport packet fits WoW limit")
    bus[#bus+1]={sender=current.player,prefix=prefix,msg=msg,channel=channel,target=target}
end}
local function client(name)
    local c={Model=M,player=name.."-Hyjal",scope="Hyjal:Alliance:STO",records={},members={},frames={},online=true}
    function c:Name(s) return M.Name(s,"Hyjal") end
    function c:Print() end
    function c:Changed() self.changed=(self.changed or 0)+1 end
    current=c
    assert(loadfile("STORedFlag/Sync.lua"))("STORedFlag",c)
    c:InitSync()
    clients[#clients+1]=c
    return c
end
local alice,bob,charlie=client("Alice"),client("Bob"),client("Charlie")
for _,c in ipairs(clients) do for _,peer in ipairs(clients) do c.members[M.Key(peer.player)]=true end end
local function run(seconds)
    for _=1,math.ceil(seconds/.2) do
        now=now+.2
        for i=#timers,1,-1 do
            local t=timers[i]
            if t.at<=now then table.remove(timers,i); current=t.client; if current.online then t.fn() end end
        end
        for _,c in ipairs(clients) do
            if c.online then current=c; for _,f in ipairs(c.frames) do if f.OnUpdate then f:OnUpdate(.2) end end end
        end
        local pending=bus; bus={}
        for _,packet in ipairs(pending) do
            for _,c in ipairs(clients) do
                if c.online and (packet.channel=="GUILD" or packet.target==c.player) then
                    current=c; c:Receive(packet.prefix,packet.msg,packet.channel,packet.sender)
                end
            end
        end
    end
end
run(20)
charlie.online=false
local r=record(nil,string.rep("é",95),GetServerTime())
M.Merge(alice.records,r); alice:Broadcast(r)
run(5)
check(#M.Reports(bob.records,r.target)==1,"Live fragmented update reaches guild peer")
check(#M.Reports(charlie.records,r.target)==0,"Offline peer receives nothing")
charlie.online=true
run(65)
current=charlie; charlie:RequestSync()
run(20)
check(#M.Reports(charlie.records,r.target)==1,"Returning peer recovers snapshot")
charlie.online=false
local tomb=record(nil,"",GetServerTime(),true)
M.Merge(alice.records,tomb); alice:Broadcast(tomb)
run(5)
check(bob.records[M.ID(tomb)].deleted,"Live deletion removes author's report")
charlie.online=true
run(65); current=charlie; charlie:RequestSync(); run(25)
check(charlie.records[M.ID(tomb)].deleted,"Offline deletion is recovered")
check(not M.Merge(charlie.records,r),"Stale data cannot resurrect deleted report after sync")
local bad=record("Mallory-Hyjal","Forged",GetServerTime(),false,"Victime-Hyjal")
local function inject(receiver,sender,channel,data,id)
    current=receiver
    local n=math.ceil(#data/180)
    for i=n,1,-1 do receiver:Receive("STORF1","R|"..id.."|"..i.."|"..n.."|"..data:sub((i-1)*180+1,i*180),channel,sender) end
end
inject(bob,"Outsider-Hyjal","GUILD",M.Pack(bad),900)
check(not bob.records[M.ID(bad)],"Non-guild sender rejected")
inject(bob,alice.player,"GUILD",M.Pack(bad),901)
check(not bob.records[M.ID(bad)],"Live author spoof rejected")
inject(bob,alice.player,"WHISPER",M.Pack(bad),902)
check(not bob.records[M.ID(bad)],"Unsolicited snapshot rejected")
local reversed=record("Alice-Hyjal",string.rep("à",95),GetServerTime(),false,"Autre-Hyjal")
inject(bob,alice.player,"GUILD",M.Pack(reversed),903)
check(bob.records[M.ID(reversed)]~=nil,"Out of order fragments reassemble")
local before=bob.changed
inject(bob,alice.player,"GUILD",M.Pack(reversed),904)
check(bob.changed==before,"Replayed record causes no update")
local future=record("Alice-Hyjal","Future",GetServerTime()+90000,false,"Futur-Hyjal")
inject(bob,alice.player,"GUILD",M.Pack(future),905)
check(not bob.records[M.ID(future)],"Far-future revisions rejected")
current=bob; bob:Broadcast(reversed); bob:ResetSync(); run(2)
check(true,"Queue reset completes without sending stale guild data")
alice.online,bob.online,charlie.online=false,false,false
local d,e=client("Diane"),client("Emma")
d.members={[M.Key(d.player)]=true,[M.Key(e.player)]=true}; e.members=d.members
M.Merge(d.records,record(d.player,"Motif Diane",GetServerTime()))
M.Merge(e.records,record(e.player,"Motif Emma",GetServerTime()))
run(25)
check(#M.Reports(d.records,"Joueur-Hyjal")==2,"Snapshot exchange uploads missing local records")
check(#M.Reports(e.records,"Joueur-Hyjal")==2,"Snapshot exchange downloads missing remote records")
check(d.lastCompleted and e.lastCompleted,"Both directions report completion")

-- Exercise actual guild scoping, including leaving and rejoining a guild.
local core={Model=M,frames={}}
current=core
assert(loadfile("STORedFlag/Core.lua"))("STORedFlag",core)
STORedFlagDB={guilds={}}
local guild="STO"
GetGuildInfo=function() return guild end
GetNormalizedRealmName=function() return "Hyjal" end
UnitFactionGroup=function() return "Alliance" end
GetNumGuildMembers=function() return 0 end
core.player="Alice-Hyjal"
function core:Changed() end
function core:ResetSync() self.resets=(self.resets or 0)+1 end
core:RefreshGuild(); M.Merge(core.records,record())
guild="AutreGuilde"; core:RefreshGuild()
check(next(core.records)==nil,"Another guild does not see old guild records")
guild=nil; core:RefreshGuild()
check(core.records==nil and next(core.members)==nil,"Leaving guild disables access and roster")
guild="STO"; core:RefreshGuild()
check(#M.Reports(core.records,"Joueur-Hyjal")==1,"Original guild history restored on rejoin")
check(core.resets==4,"Every guild boundary cancels queued network state")
for _,file in ipairs({"Model","Core","Sync","UI","Display"}) do
    check(loadfile("STORedFlag/"..file..".lua")~=nil,file.." compiles")
end
print("PASS: "..passed.." assertions (model, sync, syntax).")
