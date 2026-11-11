-- QuestChums : le journal de quêtes du joueur et son propre état pour une quête.
--
-- Le jeu ne dit pas si un AUTRE joueur peut prendre une quête : chaque joueur équipé de
-- QuestChums calcule donc son propre état et l'envoie à la guilde. Pour « peut la prendre »,
-- l'addon se fie à ce que son jeu lui a montré :
--   1. la quête lui a été proposée par un PNJ (fenêtre de quête ou de dialogue) ;
--   2. la quête apparaît comme disponible sur sa carte (suites de quêtes, point « ! ») ;
--   3. la quête fait partie d'une suite dont il a fait l'étape précédente.
local _, ns = ...
local M = ns.Model

local AVAILABLE_DAYS = 30
local turnedIn = {}           -- quêtes rendues pendant la session (le jeu met du temps à le savoir)
local requestedMaps = {}      -- cartes dont on a demandé les suites de quêtes
local lastScan = {}           -- carte → GetTime() de la dernière lecture
local chains = {}             -- quête → liste ordonnée de sa suite (false si aucune)
local tracked                 -- id → dernier état envoyé pour les quêtes du journal

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e = pcall(fn, ...)
  if ok then return a, b, c, d, e end
end

local function isCompleted(id)
  if turnedIn[id] then return true end
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return call(C_QuestLog.IsQuestFlaggedCompleted, id) end
  return call(IsQuestFlaggedCompleted, id)
end

local function logIndex(id)
  if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then return call(C_QuestLog.GetLogIndexForQuestID, id) end
end

local function isOnQuest(id)
  if C_QuestLog and C_QuestLog.IsOnQuest then return call(C_QuestLog.IsOnQuest, id) end
  return logIndex(id) ~= nil
end

function ns:QuestMap(id)
  return call(GetQuestUiMapID, id) or (C_TaskQuest and call(C_TaskQuest.GetQuestZoneID, id)) or 0
end

function ns:QuestTitle(id)
  return (C_QuestLog and call(C_QuestLog.GetTitleForQuestID, id)) or ("Quête " .. id)
end

-- Quêtes du journal, dans l'ordre du journal : { id, title, level, header, map }.
-- Les quêtes cachées, de monde et d'expédition ne sont pas listées.
function ns:MyQuests()
  local list = {}
  if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return list end
  local header
  for i = 1, C_QuestLog.GetNumQuestLogEntries() do
    local info = C_QuestLog.GetInfo(i)
    if info and info.isHeader then
      header = info.title
    elseif info and info.questID and info.questID > 0 and not info.isHidden and not info.isTask and not info.isBounty then
      list[#list + 1] = { id = info.questID, title = info.title or ns:QuestTitle(info.questID),
        level = info.level, header = header, map = ns:QuestMap(info.questID) }
    end
  end
  return list
end

local function progress(id)
  local ready = (C_QuestLog.ReadyForTurnIn and call(C_QuestLog.ReadyForTurnIn, id))
    or (C_QuestLog.IsComplete and call(C_QuestLog.IsComplete, id))
  return M.ProgressState(C_QuestLog.GetQuestObjectives and call(C_QuestLog.GetQuestObjectives, id), ready)
end

-- Suites de quêtes : renvoie "P" si l'étape précédente est faite, "X" sinon, nil si on ne sait pas.
local function chainState(id, map)
  if not (C_QuestLine and C_QuestLine.GetQuestLineInfo and C_QuestLine.GetQuestLineQuests) or not map or map == 0 then return end
  local quests = chains[id]
  if quests == nil then
    local info = call(C_QuestLine.GetQuestLineInfo, id, map)
    local line = info and info.questLineID
    quests = line and call(C_QuestLine.GetQuestLineQuests, line)
    chains[id] = type(quests) == "table" and quests or false
  end
  if type(quests) ~= "table" then return end
  for i, q in ipairs(quests) do
    if q == id then
      if i == 1 then return nil end
      return isCompleted(quests[i - 1]) and "P" or "X"
    end
  end
end

local function markAvailable(id)
  if M.ValidID(id) then QuestChumsCharDB.available[id] = GetServerTime() end
end

-- Lit les suites de quêtes disponibles sur une carte (réponse asynchrone du jeu).
local function scanMap(map, force)
  if not (C_QuestLine and C_QuestLine.GetAvailableQuestLines) or not map or map == 0 then return end
  if not force and lastScan[map] and GetTime() - lastScan[map] < 30 then return end
  lastScan[map] = GetTime()
  local lines = call(C_QuestLine.GetAvailableQuestLines, map)
  for _, l in ipairs(type(lines) == "table" and lines or {}) do
    if l.questID and not l.isHidden then markAvailable(l.questID) end
  end
end

local function requestMap(map)
  if not map or map == 0 or requestedMaps[map] then return end
  requestedMaps[map] = true
  if C_QuestLine and C_QuestLine.RequestQuestLinesForMap then call(C_QuestLine.RequestQuestLinesForMap, map) end
  scanMap(map, true)
end

-- Mon état pour une quête (voir Model.lua pour les codes).
function ns:OwnState(id, map)
  if isOnQuest(id) then return progress(id) end
  if isCompleted(id) then return "D" end
  local seen = QuestChumsCharDB.available[id]
  if seen and GetServerTime() - seen < AVAILABLE_DAYS * 86400 then return "P" end
  if map and map > 0 then
    requestMap(map)
    scanMap(map)
    if QuestChumsCharDB.available[id] then return "P" end
  end
  return chainState(id, map) or "N"
end

-- Compare le journal au dernier état envoyé et diffuse ce qui a changé.
function ns:CheckOwnChanges()
  local current, changes = {}, {}
  for _, q in ipairs(self:MyQuests()) do current[q.id] = self:OwnState(q.id, q.map) end
  if tracked then
    for id, s in pairs(current) do
      if tracked[id] ~= s then changes[#changes + 1] = { id = id, s = s } end
    end
    for id in pairs(tracked) do
      if not current[id] then changes[#changes + 1] = { id = id, s = self:OwnState(id) } end
    end
  else
    for id, s in pairs(current) do changes[#changes + 1] = { id = id, s = s } end
  end
  tracked = current
  if #changes > 0 and self.SendStates then self:SendStates(changes) end
  if self.RecheckAnswered then self:RecheckAnswered() end
  self:Changed()
end

local function recordOffered()
  -- Fenêtre de dialogue d'un PNJ : quêtes proposées.
  if C_GossipInfo and C_GossipInfo.GetAvailableQuests then
    for _, q in ipairs(call(C_GossipInfo.GetAvailableQuests) or {}) do markAvailable(q.questID) end
  end
end

local function recordGreeting()
  local n = call(GetNumAvailableQuests) or 0
  for i = 1, n do
    local _, _, _, _, id = call(GetAvailableQuestInfo, i)
    markAvailable(id)
  end
end

function ns:InitQuests()
  local limit = GetServerTime() - AVAILABLE_DAYS * 86400
  for id, t in pairs(QuestChumsCharDB.available) do
    if type(t) ~= "number" or t < limit then QuestChumsCharDB.available[id] = nil end
  end

  local f = CreateFrame("Frame")
  local pending = false
  local function schedule(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay or 1, function() pending = false; ns:CheckOwnChanges() end)
  end
  for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
    "QUEST_DETAIL", "GOSSIP_SHOW", "QUEST_GREETING", "QUESTLINE_UPDATE", "ZONE_CHANGED_NEW_AREA" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", function(_, event, a, b)
    if event == "QUEST_TURNED_IN" then
      if M.ValidID(a) then turnedIn[a] = true end
    elseif event == "QUEST_ACCEPTED" then
      local id = M.ValidID(b) and b or a      -- Classic : (index, questID) ; moderne : (questID)
      if M.ValidID(id) and ns.AskAbout then ns:AskAbout(id, ns:QuestMap(id)) end
    elseif event == "QUEST_DETAIL" then
      markAvailable(call(GetQuestID))
    elseif event == "GOSSIP_SHOW" then
      recordOffered()
    elseif event == "QUEST_GREETING" then
      recordGreeting()
    elseif event == "QUESTLINE_UPDATE" then
      for map in pairs(requestedMaps) do scanMap(map, true) end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
      requestMap(C_Map and call(C_Map.GetBestMapForUnit, "player"))
    end
    schedule(event == "QUEST_LOG_UPDATE" and 1 or 0.5)
  end)
  requestMap(C_Map and call(C_Map.GetBestMapForUnit, "player"))
end
