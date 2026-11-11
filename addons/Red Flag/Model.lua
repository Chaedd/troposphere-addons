local _, A = ...
A.Model = {}
local M = A.Model
M.MAX_RECORDS = 3000

function M.Plain(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("|", ""):gsub("[%z\1-\31\127]", " "):match("^%s*(.-)%s*$"))
end

-- Full realm names are mandatory on the wire. Never match another realm by short name.
function M.Name(s, realm)
    if type(s) ~= "string" or #s > 100 then return nil end
    s = s:match("^%s*(.-)%s*$")
    local name, server = s:match("^([^%-]+)%-(.+)$")
    if not name then name, server = s, realm end
    if not server then return nil end
    server = server:gsub("%s", "")
    if name == "" or server == "" or name:find("[%s|%%:%c%d]") or server:find("[|%%:%c]") then return nil end
    return name .. "-" .. server
end

function M.Key(name)
    return (strlower or string.lower)(name)
end

-- Forever names are first name + surname, not Name-Realm. Keep the v0.1.0
-- hyphenated storage identity, but accept native roster/chat names and the
-- extra realm suffix supplied by CHAT_MSG_ADDON.
function M.CharacterName(s)
    if type(s) ~= "string" or #s > 100 then return nil end
    s = s:match("^%s*(.-)%s*$")
    local first, surname, suffix = s:match("^([^%s%-]+)[ %-]([^%s%-]+)(.*)$")
    if not first or (suffix ~= "" and not suffix:match("^%-[^%s|%%:%c]+$")) then return nil end
    local name = first .. "-" .. surname
    if M.Name(name) ~= name then return nil end
    return name
end

function M.WhisperTarget(name)
    local canonical = M.CharacterName(name)
    return canonical and canonical:gsub("%-", " ")
end

function M.Valid(r)
    return type(r) == "table" and type(r.target) == "string" and type(r.author) == "string"
        and M.Name(r.target) == r.target and M.Name(r.author) == r.author
        and type(r.rev) == "number" and r.rev >= 1 and r.rev < 1e14 and r.rev == math.floor(r.rev)
        and type(r.deleted) == "boolean" and type(r.reason) == "string" and #r.reason <= 200
        and r.reason == M.Plain(r.reason) and (r.deleted or #r.reason > 0)
end

function M.ID(r) return M.Key(r.target) .. ":" .. M.Key(r.author) end

function M.Merge(records, r)
    if not M.Valid(r) then return false end
    local id = M.ID(r)
    local old = records[id]
    if not old then
        local count = 0
        for _ in pairs(records) do count = count + 1 end
        if count >= M.MAX_RECORDS then return false end
    else
        -- Deterministic conflict resolution, including two simultaneous sessions of one character.
        local a = (r.deleted and "1" or "0") .. r.reason
        local b = (old.deleted and "1" or "0") .. old.reason
        if r.rev < old.rev or (r.rev == old.rev and a <= b) then return false end
    end
    records[id] = {target=r.target, author=r.author, rev=r.rev, reason=r.reason, deleted=r.deleted}
    return true
end

function M.Reports(records, target)
    local out = {}
    local key = target and M.Key(target)
    for _, r in pairs(records or {}) do
        if not r.deleted and M.Key(r.target) == key then out[#out+1] = r end
    end
    table.sort(out, function(a,b) return M.Key(a.author) < M.Key(b.author) end)
    return out
end

local function encode(s)
    return (s:gsub("([^%w%-%._ ])", function(c) return string.format("%%%02X", string.byte(c)) end))
end
local function decode(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h,16)) end))
end
function M.Pack(r)
    return table.concat({encode(r.target),encode(r.author),string.format("%.0f",r.rev),r.deleted and "1" or "0",encode(r.reason)}, "|")
end
function M.Unpack(s)
    if type(s) ~= "string" or #s > 2000 then return nil end
    local t,a,v,d,r = s:match("^([^|]+)|([^|]+)|(%d+)|([01])|([^|]*)$")
    if not t then return nil end
    local record = {target=decode(t),author=decode(a),rev=tonumber(v),deleted=d=="1",reason=decode(r)}
    if M.Valid(record) then return record end
end
