-- QuestTarget : un bouton à côté de chaque quête du suivi d'objectifs.
-- Clic gauche : cible le mob le plus proche lié à la quête (à tuer ou à looter).
--
-- D'où viennent les noms des mobs :
--   1. objectifs « tuer » : le nom est dans le texte de l'objectif (« Sanglier tué : 2/8 ») ;
--   2. objectifs « looter » : le jeu ne donne pas le nom du mob, donc l'addon l'apprend
--      en lisant l'infobulle des mobs proches (barres de vie / survol / cible) : les mobs
--      utiles à une quête y affichent le titre de la quête. Les noms appris sont gardés.
--
-- Cibler est une action protégée : seul un bouton sécurisé (macro /targetexact) peut le
-- faire, et ses réglages ne peuvent pas changer en combat. Les boutons sont donc mis à
-- jour hors combat ; en combat ils gardent leur dernier état.

local ADDON = ...
local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local VERSION = GetMeta and GetMeta(ADDON, "Version") or "?"

local ICON = "Interface\\Icons\\Ability_Hunter_SniperShot"
local BUTTON_SIZE = 16
local MAX_MACRO = 255
local MARK_BUTTON = "QuestTargetMarkButton"

BINDING_HEADER_QUESTTARGET = "QuestTarget"
_G["BINDING_NAME_CLICK QuestTargetSuperButton:LeftButton"] = "Cibler un mob de la quête suivie"

local db
local modules = {}
local buttons = {}   -- questID -> bouton affiché
local pool = {}      -- boutons libres
local pendingUpdate = false
local updateQueued = false
local superButton
local markButton
local optionsFrame
local RefreshOptions
local MARKER_NAMES = { "Étoile", "Cercle", "Losange", "Triangle", "Lune", "Carré", "Croix", "Tête de mort" }

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99QuestTarget|r : " .. msg)
end

local function IsSecret(v)
	return issecretvalue and issecretvalue(v) or false
end

------------------------------------------------------------------------
-- Noms des mobs à partir du texte des objectifs

local killWords = {}
do
	local function addWordsFrom(fmt)
		if type(fmt) ~= "string" then return end
		local s = fmt:gsub("%%%d?%$?[sd]", " "):gsub("[:/]", " ")
		for w in s:gmatch("%S+") do killWords[w:lower()] = true end
	end
	addWordsFrom(QUEST_MONSTERS_KILLED)
	addWordsFrom(QUEST_MONSTERS_KILLED_NOPROGRESS)
	for _, w in ipairs({ "slain", "killed", "tué", "tués", "tuée", "tuées", "tué(s)", "tué(e)", "tué(e)s",
		"vaincu", "vaincus", "vaincue", "vaincues", "vaincu(s)", "éliminé", "éliminés", "éliminé(s)" }) do
		killWords[w] = true
	end
end

local function MobNameFromObjective(text)
	if type(text) ~= "string" or IsSecret(text) then return end
	-- le français met une espace insécable (U+00A0 ou U+202F) avant « : » :
	-- invisible, mais elle empêchait /targetexact de trouver le mob
	local s = text:gsub("\194\160", " "):gsub("\226\128\175", " ")
	s = s:gsub("%d+%s*/%s*%d+", " "):gsub(":", " ")
	local words = {}
	for w in s:gmatch("%S+") do
		if not killWords[w:lower()] then words[#words + 1] = w end
	end
	local name = strtrim(table.concat(words, " "), " ,.-")
	if name ~= "" then return name end
end

------------------------------------------------------------------------
-- Titres des quêtes du journal (pour reconnaître les infobulles)

local titleToQuest = {}
local titlesDirty = true

local function GetTitles()
	if titlesDirty then
		wipe(titleToQuest)
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.questID and info.title then
				titleToQuest[info.title] = info.questID
			end
		end
		titlesDirty = false
	end
	return titleToQuest
end

local function GetQuestMobNames(questID)
	local names, seen = {}, {}
	local function add(n)
		if n and not seen[n] then
			seen[n] = true
			names[#names + 1] = n
		end
	end

	if C_QuestLog.IsComplete(questID) then return names end

	local objectives = C_QuestLog.GetQuestObjectives(questID)
	if objectives then
		for _, o in ipairs(objectives) do
			if not o.finished and o.type == "monster" then
				add(MobNameFromObjective(o.text))
			end
		end
	end

	local learned = db.learned[questID]
	if learned then
		local list = {}
		for n in pairs(learned) do list[#list + 1] = n end
		table.sort(list)
		for _, n in ipairs(list) do add(n) end
	end
	return names
end

------------------------------------------------------------------------
-- Mobs visibles (barres de vie) : vivants et pas engagés par un autre joueur

local MAX_PLATE_LINES = 3
local plates = {}
local platesOn = false

local function CollectPlates()
	wipe(plates)
	platesOn = GetCVarBool and GetCVarBool("nameplateShowEnemies") or false
	if not C_NamePlate or not C_NamePlate.GetNamePlates then
		platesOn = false
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		-- Attention : les barres de vie sont des zones protégées, on ne peut pas
		-- lire leur position (GetBottom, GetTop...) sans provoquer une erreur.
		local unit = plate.unitToken or plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit and UnitExists(unit) and not UnitIsPlayer(unit) and not UnitIsDead(unit) then
			local name = UnitName(unit)
			local denied = UnitIsTapDenied and UnitIsTapDenied(unit)
			local combat = UnitAffectingCombat(unit)
			if name and not IsSecret(name) and not IsSecret(denied) and not denied then
				-- proche = à moins de ~28 m (distance de « suivre »), si le jeu veut bien le dire
				local ok, near = pcall(CheckInteractDistance, unit, 4)
				plates[#plates + 1] = {
					unit = unit,
					name = name,
					-- un mob en combat qui ne nous vise pas est sans doute pris par quelqu'un d'autre
					busy = IsSecret(combat) or (combat and not UnitIsUnit(unit .. "target", "player")) or false,
					near = ok and not IsSecret(near) and near and true or false,
					index = #plates + 1,
				}
			end
		end
	end
end

-- Macro du bouton.
-- Barres de vie ennemies affichées : on cible directement les mobs de la quête
-- vivants et non engagés par d'autres joueurs (/target nameplateN). Le meilleur
-- est mis en dernier, car chaque ligne remplace la précédente : libre avant
-- « en combat », puis proche (moins de ~28 m) avant lointain.
-- Sinon (barres masquées) : ciblage par nom, sans pouvoir filtrer les mobs déjà
-- engagés ; un cadavre ciblé est relâché et on essaie le nom suivant.
-- La liste des barres de vie est figée en combat (le jeu l'impose) : elle peut
-- donc être périmée après un kill. On complète alors par un ciblage par nom.
-- Si rien n'est trouvé, on reprend l'ancienne cible, sauf si elle est morte
-- (sinon le bouton reciblait le cadavre qu'on vient de tuer).
local function BuildMacro(names)
	local lines = { "/cleartarget" }
	-- Marquer avant de reprendre l'ancienne cible : si la recherche échoue,
	-- celle-ci ne doit pas recevoir la tête de mort par erreur.
	local tail = "/targetlasttarget [noexists]\n/cleartarget [dead]"
	if db and db.skull then
		tail = "/click [@target,harm,nodead] " .. MARK_BUTTON .. " LeftButton 0\n" .. tail
	end
	local len = #lines[1] + 1 + #tail
	local function push(l)
		if len + #l + 1 > MAX_MACRO then return false end
		lines[#lines + 1] = l
		len = len + #l + 1
		return true
	end

	local free = 0
	if platesOn then
		local wanted = {}
		for _, n in ipairs(names) do wanted[n] = true end
		local cands = {}
		for _, p in ipairs(plates) do
			if wanted[p.name] then cands[#cands + 1] = p end
		end
		table.sort(cands, function(a, b)
			if a.busy ~= b.busy then return not a.busy end
			if a.near ~= b.near then return a.near end
			return a.index < b.index
		end)
		free = #cands
		-- Réserver d'abord les meilleurs candidats ; une macro pleine ne doit
		-- pas conserver les moins bons et écarter le premier du classement.
		local selected, selectedLen = {}, len
		for i = 1, math.min(#cands, MAX_PLATE_LINES) do
			local u = cands[i].unit
			local line = ("/target [@%s,exists,nodead] %s"):format(u, u)
			if selectedLen + #line + 1 > MAX_MACRO then break end
			selected[#selected + 1] = line
			selectedLen = selectedLen + #line + 1
		end
		for i = #selected, 1, -1 do
			push(selected[i])
		end
	end
	do
		local full = false
		for pass = 1, 2 do
			for _, n in ipairs(names) do
				if not push("/targetexact [noexists] " .. n .. "\n/cleartarget [dead]") then
					full = true
					break
				end
			end
			if full then break end
		end
	end

	lines[#lines + 1] = tail
	return table.concat(lines, "\n"), free
end

------------------------------------------------------------------------
-- Marquage par une action Blizzard sécurisée, appelée depuis la macro.
-- Un HookScript Lua reste non sécurisé, même sur un bouton sécurisé ; pcall
-- ne permet pas d'y appeler SetRaidTarget lorsque le client le protège.
-- Les permissions de marquage en groupe restent gérées par le jeu.

local SKULL = 8
local function CreateMarkButton()
	local b = CreateFrame("Button", MARK_BUTTON, UIParent, "SecureActionButtonTemplate")
	markButton = b
	b:SetSize(1, 1)
	b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	b:RegisterForClicks("LeftButtonUp")
	-- /click transmet explicitement un relâchement, indépendamment du réglage
	-- ActionButtonUseKeyDown et du clic / raccourci utilisé pour cibler.
	b:SetAttribute("useOnKeyDown", false)
	b:SetAttribute("type1", "raidtarget")
	b:SetAttribute("unit", "target")
	b:SetAttribute("marker1", db.marker)
	-- Ne pas basculer le signe à chaque clic sur le même mob.
	b:SetAttribute("action1", "set")
end

------------------------------------------------------------------------
-- Boutons

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Cibler les mobs de la quête")
	if self.names and #self.names > 0 then
		for _, n in ipairs(self.names) do GameTooltip:AddLine("- " .. n, 1, 1, 1) end
	end
	if platesOn then
		GameTooltip:AddLine(("%d mob(s) libre(s) visible(s)"):format(self.free or 0), 0.4, 1, 0.4)
	else
		GameTooltip:AddLine("Affiche les barres de vie ennemies (V) pour ignorer les mobs déjà pris par d'autres joueurs.", 1, 0.6, 0.2, true)
	end
	GameTooltip:AddLine("Clic gauche : cibler le plus proche", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("Clic droit : liste dans le chat", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

local function PrintNames(self)
	local title = self.questID and C_QuestLog.GetTitleForQuestID(self.questID) or "?"
	if self.names and #self.names > 0 then
		Print(("%s : %s"):format(title, table.concat(self.names, ", ")))
	else
		Print(("%s : aucun mob connu."):format(title))
	end
end

local function AcquireButton()
	local b = tremove(pool)
	if b then return b end
	b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
	b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("type1", "macro")
	b:SetNormalTexture(ICON)
	b:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetScript("OnEnter", ShowTooltip)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:HookScript("OnClick", function(self, button, down)
		if button == "RightButton" then
			if not down then PrintNames(self) end
		end
	end)
	return b
end

local function SetMacro(b, names)
	local macro, free = BuildMacro(names)
	if b.macro ~= macro then
		b:SetAttribute("macrotext1", macro)
		b.macro = macro
	end
	b.names = names
	b.free = free
end

-- Position absolue sur UIParent (pas d'ancrage sur le suivi, qui bouge en combat)
local function PlaceButton(b, block)
	local left, top = block:GetLeft(), block:GetTop()
	if not (left and top) then return false end
	local header = block.HeaderText
	local y = top - 8
	if header and header:GetTop() and header:GetBottom() then
		y = (header:GetTop() + header:GetBottom()) / 2
	end
	local poi = block.poiButton or block.POIButton
	if poi and poi:IsShown() and poi:GetLeft() then
		left = math.min(left, poi:GetLeft())
	end
	local scale = block:GetEffectiveScale() / UIParent:GetEffectiveScale()
	-- même couche que le suivi : les sacs et fenêtres passent devant le bouton
	local strata, level = block:GetFrameStrata(), block:GetFrameLevel() + 5
	if b:GetFrameStrata() ~= strata then b:SetFrameStrata(strata) end
	if b:GetFrameLevel() ~= level then b:SetFrameLevel(level) end
	b:ClearAllPoints()
	b:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", left * scale - 2, y * scale)
	b:Show()
	return true
end

local function ForEachQuestBlock(fn)
	for _, module in ipairs(modules) do
		if module.usedBlocks and (not module.IsVisible or module:IsVisible()) then
			for _, t in pairs(module.usedBlocks) do
				if type(t) == "table" then
					if t.GetLeft then
						fn(t.id, t)
					else
						for id, block in pairs(t) do
							if type(block) == "table" and block.GetLeft then fn(block.id or id, block) end
						end
					end
				end
			end
		end
	end
end

local function UpdateSuperButton(firstQuest)
	if not superButton then return end
	local questID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
	local names = (questID and questID > 0) and GetQuestMobNames(questID) or {}
	if #names == 0 and firstQuest then
		questID = firstQuest
		names = GetQuestMobNames(firstQuest)
	end
	superButton.questID = questID
	SetMacro(superButton, names)
end

local function UpdateButtons()
	updateQueued = false
	if not db then return end
	if InCombatLockdown() then
		pendingUpdate = true
		return
	end
	pendingUpdate = false
	if markButton:GetAttribute("marker1") ~= db.marker then
		markButton:SetAttribute("marker1", db.marker)
	end
	CollectPlates()

	local used, firstQuest = {}, nil
	ForEachQuestBlock(function(questID, block)
		if type(questID) ~= "number" or used[questID] or not block:IsVisible() then return end
		if not C_QuestLog.GetLogIndexForQuestID(questID) then return end
		local names = GetQuestMobNames(questID)
		if #names == 0 then return end
		local b = buttons[questID] or AcquireButton()
		b.questID = questID
		SetMacro(b, names)
		if PlaceButton(b, block) then
			buttons[questID] = b
			used[questID] = true
			firstQuest = firstQuest or questID
		else
			b:Hide()
			buttons[questID] = nil
			pool[#pool + 1] = b
		end
	end)

	for questID, b in pairs(buttons) do
		if not used[questID] then
			b:Hide()
			b:ClearAllPoints()
			buttons[questID] = nil
			pool[#pool + 1] = b
		end
	end

	UpdateSuperButton(firstQuest)
end

local function QueueUpdate()
	if updateQueued then return end
	updateQueued = true
	C_Timer.After(0.1, UpdateButtons)
end

------------------------------------------------------------------------
-- Options et bouton de minicarte (sans dépendance externe).
-- db.skull reste le réglage d'activation pour préserver les anciens profils.

local function SettingsChanged()
	if InCombatLockdown() then
		pendingUpdate = true
	else
		UpdateButtons()
	end
	if RefreshOptions then RefreshOptions() end
end

local function ToggleOptions()
	if optionsFrame:IsShown() then optionsFrame:Hide() else optionsFrame:Show() end
end

local function CreateOptions()
	local f = CreateFrame("Frame", "QuestTargetOptionsFrame", UIParent, "BackdropTemplate")
	optionsFrame = f
	f:SetSize(400, 350)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetScript("OnHide", f.StopMovingOrSizing)
	f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16,
		edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 22, -22)
	title:SetText("QuestTarget")
	local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", 22, -47)
	subtitle:SetText("Choisis ton signe pour repérer les mobs ciblés.")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	local enabled = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	enabled:SetPoint("TOPLEFT", 20, -70)
	local label = enabled:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", enabled, "RIGHT", 4, 0)
	label:SetText("Marquer les mobs ciblés")
	enabled:SetScript("OnClick", function(self)
		db.skull = self:GetChecked() and true or false
		SettingsChanged()
	end)
	local choices = {}
	for i = 1, 8 do
		local marker = i
		local b = CreateFrame("Button", nil, f, "BackdropTemplate")
		choices[i] = b
		b:SetSize(48, 48)
		b:SetPoint("TOPLEFT", 41 + ((i - 1) % 4) * 90, -118 - math.floor((i - 1) / 4) * 78)
		b:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
		local icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetSize(32, 32)
		icon:SetPoint("CENTER")
		icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
		SetRaidTargetIconTexture(icon, marker)
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		local name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		name:SetPoint("TOP", b, "BOTTOM", 0, -3)
		name:SetText(MARKER_NAMES[marker])
		b:SetScript("OnClick", function()
			db.marker = marker
			SettingsChanged()
		end)
	end
	local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("TOPLEFT", 22, -278)
	status:SetWidth(356)
	status:SetJustifyH("LEFT")
	local note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("BOTTOMLEFT", 22, 18)
	note:SetText("Réglages enregistrés pour ce personnage.")
	RefreshOptions = function()
		enabled:SetChecked(db.skull)
		for i, b in ipairs(choices) do
			if i == db.marker then b:SetBackdropBorderColor(1, 0.82, 0)
			else b:SetBackdropBorderColor(0.35, 0.35, 0.35) end
		end
		if InCombatLockdown() then
			status:SetText("|cffffcc00En combat : les modifications seront appliquées à la sortie du combat.|r")
		else
			status:SetText(db.skull and ("Signe actif : " .. MARKER_NAMES[db.marker]) or "Marquage désactivé.")
		end
	end
	f:SetScript("OnShow", RefreshOptions)
	tinsert(UISpecialFrames, "QuestTargetOptionsFrame")
	f:Hide()
	RefreshOptions()
end

local function CreateMinimapButton()
	local b = CreateFrame("Button", "QuestTargetMinimapButton", Minimap)
	b:SetSize(32, 32)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
	b:RegisterForClicks("LeftButtonUp")
	b:RegisterForDrag("LeftButton")
	local icon = b:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER")
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetSize(54, 54)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
	local function Position()
		local angle = math.rad(db.minimapAngle)
		b:ClearAllPoints()
		b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * (Minimap:GetWidth() / 2 + 8),
			math.sin(angle) * (Minimap:GetHeight() / 2 + 8))
	end
	b:SetScript("OnMouseDown", function(self) self.dragged = false end)
	b:SetScript("OnClick", function(self) if not self.dragged then ToggleOptions() end end)
	b:SetScript("OnDragStart", function(self)
		self.dragged = true
		GameTooltip:Hide()
		self:SetScript("OnUpdate", function()
			local x, y = GetCursorPosition()
			local cx, cy = Minimap:GetCenter()
			local scale = Minimap:GetEffectiveScale()
			if not cx or not cy then return end
			db.minimapAngle = math.deg(math.atan2(y / scale - cy, x / scale - cx))
			Position()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("QuestTarget")
		GameTooltip:AddLine(db.skull and ("Signe : " .. MARKER_NAMES[db.marker]) or "Marquage désactivé", 1, 1, 1)
		GameTooltip:AddLine("Clic gauche : options", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Glisser : déplacer autour de la minicarte", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	Minimap:HookScript("OnSizeChanged", Position)
	Position()
end

------------------------------------------------------------------------
-- Apprentissage des mobs par leur infobulle

local function LearnFromUnit(unit)
	if not db or InCombatLockdown() then return end
	if not UnitExists(unit) or UnitIsPlayer(unit) or UnitIsDead(unit) then return end
	local name = UnitName(unit)
	if not name or IsSecret(name) then return end
	local data = C_TooltipInfo and C_TooltipInfo.GetUnit and C_TooltipInfo.GetUnit(unit)
	if not data or not data.lines then return end

	local titles = GetTitles()
	local changed = false
	for _, line in ipairs(data.lines) do
		local text = line.leftText
		if type(text) == "string" and not IsSecret(text) then
			local questID = titles[text]
			if questID then
				db.learned[questID] = db.learned[questID] or {}
				if not db.learned[questID][name] then
					db.learned[questID][name] = true
					changed = true
				end
			end
		end
	end
	if changed then QueueUpdate() end
end

local function ScanNamePlates()
	if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.unitToken or plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit then LearnFromUnit(unit) end
	end
end

------------------------------------------------------------------------
-- Démarrage

local function HookTracker()
	for _, name in ipairs({ "QuestObjectiveTracker", "CampaignQuestObjectiveTracker",
		"QUEST_TRACKER_MODULE", "CAMPAIGN_QUEST_TRACKER_MODULE" }) do
		local m = _G[name]
		if type(m) == "table" then
			modules[#modules + 1] = m
			for _, fn in ipairs({ "Update", "LayoutContents" }) do
				if type(m[fn]) == "function" then hooksecurefunc(m, fn, QueueUpdate) end
			end
		end
	end
	if type(ObjectiveTracker_Update) == "function" then
		hooksecurefunc("ObjectiveTracker_Update", QueueUpdate)
	end
	if ObjectiveTrackerFrame then
		ObjectiveTrackerFrame:HookScript("OnShow", QueueUpdate)
		ObjectiveTrackerFrame:HookScript("OnHide", QueueUpdate)
		ObjectiveTrackerFrame:HookScript("OnSizeChanged", QueueUpdate)
	end
	if #modules == 0 then
		Print("suivi des objectifs introuvable, aucun bouton ne sera affiché.")
	end
end

local function CreateSuperButton()
	superButton = CreateFrame("Button", "QuestTargetSuperButton", UIParent, "SecureActionButtonTemplate")
	superButton:SetSize(1, 1)
	superButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	superButton:RegisterForClicks("AnyUp", "AnyDown")
	superButton:SetAttribute("type1", "macro")
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "PLAYER_LOGIN" then
		QuestTargetDB = QuestTargetDB or {}
		db = QuestTargetDB
		db.learned = db.learned or {}
		if db.skull == nil then db.skull = true end
		if type(db.marker) ~= "number" or db.marker % 1 ~= 0 or not MARKER_NAMES[db.marker] then
			db.marker = SKULL
		end
		if type(db.minimapAngle) ~= "number" or db.minimapAngle ~= db.minimapAngle
			or db.minimapAngle == math.huge or db.minimapAngle == -math.huge then db.minimapAngle = 225 end

		CreateMarkButton()
		CreateSuperButton()
		HookTracker()
		CreateOptions()
		CreateMinimapButton()

		self:RegisterEvent("QUEST_LOG_UPDATE")
		self:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
		self:RegisterEvent("QUEST_REMOVED")
		self:RegisterEvent("SUPER_TRACKING_CHANGED")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:RegisterEvent("PLAYER_REGEN_DISABLED")
		self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
		self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
		self:RegisterEvent("PLAYER_TARGET_CHANGED")

		-- suit les mobs visibles (pris / libres / morts) et repositionne les
		-- boutons si le suivi est déplacé (MoveAny, etc.)
		C_Timer.NewTicker(0.25, function()
			if not InCombatLockdown() then QueueUpdate() end
		end)
		QueueUpdate()
	elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_LIST_CHANGED" then
		titlesDirty = true
		QueueUpdate()
	elseif event == "QUEST_REMOVED" then
		if arg1 then db.learned[arg1] = nil end
		titlesDirty = true
		QueueUpdate()
	elseif event == "SUPER_TRACKING_CHANGED" then
		QueueUpdate()
	elseif event == "PLAYER_REGEN_ENABLED" then
		ScanNamePlates()
		if pendingUpdate then QueueUpdate() end
		RefreshOptions()
	elseif event == "PLAYER_REGEN_DISABLED" then
		RefreshOptions()
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		LearnFromUnit(arg1)
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		LearnFromUnit("mouseover")
	elseif event == "PLAYER_TARGET_CHANGED" then
		LearnFromUnit("target")
	end
end)

------------------------------------------------------------------------
-- /questtarget (ou /qtg)

SLASH_QUESTTARGET1 = "/questtarget"
SLASH_QUESTTARGET2 = "/qtg"
SlashCmdList["QUESTTARGET"] = function(msg)
	msg = strtrim((msg or ""):lower())
	if msg == "reset" then
		wipe(db.learned)
		Print("mobs appris effacés.")
		QueueUpdate()
	elseif msg == "skull" then
		db.skull = not db.skull
		Print("marquage sur la cible : " .. (db.skull and "activé" or "désactivé"))
		SettingsChanged()
		if InCombatLockdown() then
			Print("le changement sera appliqué aux boutons à la sortie du combat.")
		end
	elseif msg == "options" or msg == "" then
		ToggleOptions()
	elseif msg == "debug" then
		Print(("barres de vie : %s, mobs vivants libres vus : %d"):format(platesOn and "oui" or "non", #plates))
		for _, p in ipairs(plates) do
			Print(("  %s = %s%s%s"):format(p.unit, p.name, p.busy and " (en combat)" or "", p.near and " (proche)" or ""))
		end
		for questID, b in pairs(buttons) do
			Print(("%s :"):format(C_QuestLog.GetTitleForQuestID(questID) or questID))
			Print("  noms : " .. table.concat(b.names or {}, ", "))
			Print("  macro : " .. (b.macro or "?"):gsub("\n", " | "))
		end
	elseif msg == "list" then
		local any = false
		for questID, names in pairs(db.learned) do
			local list = {}
			for n in pairs(names) do list[#list + 1] = n end
			if #list > 0 then
				any = true
				Print(("%s : %s"):format(C_QuestLog.GetTitleForQuestID(questID) or questID, table.concat(list, ", ")))
			end
		end
		if not any then Print("aucun mob appris pour l'instant.") end
	else
		Print("version " .. VERSION)
		Print("/qtg list : mobs appris par quête")
		Print("/qtg reset : oublier les mobs appris")
		Print("/qtg : ouvrir les options (activation et choix du signe)")
		Print("/qtg skull : activer / désactiver le marquage sur la cible")
		Print("Raccourci : Options > Raccourcis > AddOns > QuestTarget")
	end
end
