// Génère la base « quête -> mobs » de QuestTarget à partir des données Forever
// de QuestieDB (https://github.com/Questie/QuestieDB).
//
// Usage : node build-db.js <dossier des sources> <dossier de QuestTarget>
// Le dossier des sources contient les fichiers bruts de QuestieDB :
//   data_Forever_foreverQuestDB.lua, data_Forever_foreverItemDB.lua,
//   data_Forever_foreverNpcDB.lua, l10n_Forever_lookupNpcs_<locale>.lua
//
// Les fichiers sources sont lus comme des données : ce script ne les exécute pas,
// il décode seulement les tables Lua littérales qu'ils contiennent.

const fs = require("fs");
const path = require("path");

const [srcDir, outDir] = process.argv.slice(2);
if (!srcDir || !outDir) {
	console.error("usage : node build-db.js <sources> <dossier QuestTarget>");
	process.exit(1);
}

const MAX_DROP_NPCS = 15; // au-delà, un objet tombe un peu partout : peu utile pour cibler
const LOCALES = ["frFR", "deDE", "esES", "esMX", "koKR", "ptBR", "ruRU", "zhCN", "zhTW"];

// --- décodeur de tables Lua littérales (nombres, chaînes, nil, booléens, tables)
function parseLuaTable(text, start) {
	let i = start;
	const ws = () => {
		for (;;) {
			while (i < text.length && /\s/.test(text[i])) i++;
			if (text.startsWith("--", i)) { while (i < text.length && text[i] !== "\n") i++; continue; }
			return;
		}
	};
	function str() {
		const q = text[i++];
		let s = "";
		while (text[i] !== q) {
			if (text[i] === "\\") {
				const c = text[i + 1];
				const map = { n: "\n", t: "\t", "\\": "\\", "'": "'", '"': '"' };
				if (c in map) { s += map[c]; i += 2; }
				else if (/\d/.test(c)) { const m = /^\d{1,3}/.exec(text.slice(i + 1)); s += String.fromCharCode(+m[0]); i += 1 + m[0].length; }
				else { s += c; i += 2; }
			} else s += text[i++];
		}
		i++;
		return s;
	}
	function value() {
		ws();
		const c = text[i];
		if (c === "{") return table();
		if (c === "'" || c === '"') return str();
		const m = /^(nil|true|false|-?[\d.]+(?:e-?\d+)?)/.exec(text.slice(i, i + 40));
		if (!m) throw new Error("valeur inattendue à " + i + " : " + text.slice(i, i + 30));
		i += m[0].length;
		if (m[0] === "nil") return null;
		if (m[0] === "true") return true;
		if (m[0] === "false") return false;
		return Number(m[0]);
	}
	function table() {
		i++; // {
		const arr = [], obj = new Map();
		let n = 1, keyed = false;
		for (;;) {
			ws();
			if (text[i] === "}") { i++; break; }
			if (text[i] === "[") {
				i++;
				const k = value(); ws(); i++; /* ] */ ws(); i++; /* = */
				obj.set(k, value()); keyed = true;
			} else {
				arr[n++ - 1] = value();
			}
			ws();
			if (text[i] === "," || text[i] === ";") i++;
		}
		return keyed ? obj : arr;
	}
	i = text.indexOf("{", i);
	return table();
}

function readTable(file, marker) {
	const text = fs.readFileSync(path.join(srcDir, file), "utf8");
	const at = text.indexOf(marker);
	if (at < 0) throw new Error(marker + " introuvable dans " + file);
	return parseLuaTable(text, at + marker.length);
}

const quests = readTable("data_Forever_foreverQuestDB.lua", "QuestieDB.questData = [[return");
const items = readTable("data_Forever_foreverItemDB.lua", "QuestieDB.itemData = [[return");
const npcs = readTable("data_Forever_foreverNpcDB.lua", "QuestieDB.npcData = [[return");

// Index 1-based de Questie -> index 0-based ici
const Q_OBJECTIVES = 9, NPC_NAME = 0, NPC_FRIENDLY = 12, ITEM_NPC_DROPS = 1;

const out = new Map(); // questID -> { k: [npc], l: [npc] }
const usedNpcs = new Set();
const isTargetable = (id) => npcs.has(id);

for (const [qid, q] of quests) {
	const obj = q[Q_OBJECTIVES];
	if (!obj) continue;
	const kill = new Set(), loot = new Set();
	for (const o of obj[0] || []) if (o && isTargetable(o[0])) kill.add(o[0]);
	for (const kc of obj[4] || []) {
		if (!kc) continue;
		if (isTargetable(kc[1])) kill.add(kc[1]);
		for (const id of kc[0] || []) if (isTargetable(id)) kill.add(id);
	}
	for (const o of obj[2] || []) {
		const item = o && items.get(o[0]);
		const drops = item && item[ITEM_NPC_DROPS];
		if (!drops || drops.length > MAX_DROP_NPCS) continue;
		for (const id of drops) if (isTargetable(id)) loot.add(id);
	}
	if (kill.size || loot.size) {
		out.set(qid, { k: [...kill], l: [...loot] });
		for (const id of kill) usedNpcs.add(id);
		for (const id of loot) usedNpcs.add(id);
	}
}

const luaStr = (s) => '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n") + '"';
const header = "-- Généré par tools/QuestTarget/build-db.js à partir des données Forever de QuestieDB\n" +
	"-- (https://github.com/Questie/QuestieDB). Ne pas modifier à la main.\n";

// quêtes : [questID] = { {mobs à tuer}, {mobs qui lâchent les objets} }
const qLines = [...out.keys()].sort((a, b) => a - b).map((id) => {
	const { k, l } = out.get(id);
	return `[${id}]={{${k.join(",")}},{${l.join(",")}}},`;
});
fs.writeFileSync(path.join(outDir, "Data", "Quests.lua"),
	header + "local _, ns = ...\nns.questMobs = {\n" + qLines.join("\n") + "\n}\n");

// noms : un fichier par langue, l'anglais sert de repli
const ids = [...usedNpcs].sort((a, b) => a - b);
function writeNames(locale, nameOf) {
	const lines = [];
	for (const id of ids) {
		const n = nameOf(id);
		if (n) lines.push(`[${id}]=${luaStr(n)},`);
	}
	const guard = locale === "enUS"
		? "if ns.mobNames then return end\n"
		: `if GetLocale() ~= "${locale}" then return end\n`;
	fs.writeFileSync(path.join(outDir, "Data", `Names_${locale}.lua`),
		header + "local _, ns = ...\n" + guard + "ns.mobNames = {\n" + lines.join("\n") + "\n}\n");
	return lines.length;
}

const counts = {};
for (const loc of LOCALES) {
	const f = `l10n_Forever_lookupNpcs_${loc}.lua`;
	if (!fs.existsSync(path.join(srcDir, f))) continue;
	const t = readTable(f, "= loadstring([[return");
	counts[loc] = writeNames(loc, (id) => { const e = t.get(id); return e && (Array.isArray(e) ? e[0] : e); });
}
counts.enUS = writeNames("enUS", (id) => npcs.get(id)[NPC_NAME]);

console.log(`quêtes : ${out.size}, mobs : ${ids.length}`, counts);
