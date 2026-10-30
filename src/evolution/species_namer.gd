class_name SpeciesNamer
extends RefCounted
## Procedural species names: a Russian common name (adjective from the most
## distinctive trait + noun from the niche) and a pseudo-Latin binomial.

const NOUNS := {
	&"grazer": ["лугоход", "травобег", "степняк", "пастбищник"],
	&"browser": ["веткоед", "листогрыз", "кустарник", "высокорог"],
	&"small_herbivore": ["травогрыз", "полёвка", "семяед", "норник"],
	&"predator": ["ловчий", "клыкач", "охотник", "рыскун"],
	&"scavenger": ["трупоед", "стервятник", "подбиральщик"],
	&"detritivore": ["землерой", "перегнойник", "листоед"],
	&"filter": ["сито", "фильтрон", "студенец"],
	&"fish": ["плавник", "чешуйник", "быстроплав"],
	&"flyer": ["летун", "порхун", "крылан"],
	&"insectivore": ["мошкоед", "ловец", "щебетун"],
	&"amphibian": ["квакун", "прыгун", "водолаз"],
	&"other": ["существо", "живец", "бродяга"],
}
const LATIN_GENUS := {
	&"grazer": "Pratambul", &"browser": "Ramivor", &"small_herbivore": "Herbirod", &"predator": "Venator",
	&"scavenger": "Necrophag", &"detritivore": "Humivor", &"filter": "Colator", &"fish": "Natator",
	&"flyer": "Volucr", &"insectivore": "Muscicap", &"amphibian": "Ranoid", &"other": "Vivens",
}
const GENUS_ENDINGS := ["us", "ia", "ops", "odon", "ix", "erus", "oides"]
## trait id → [Russian adjective (high value), Latin epithet (high), Russian (low), Latin (low)]
const TRAIT_WORDS := {
	&"size": ["Великий", "magnus", "Малый", "minor"],
	&"fur_length": ["Мохнатый", "villosus", "Гладкий", "glaber"],
	&"fat_reserve": ["Тучный", "obesus", "Поджарый", "gracilis"],
	&"limb_length": ["Длинноногий", "longipes", "Коротконогий", "brevipes"],
	&"armor": ["Панцирный", "loricatus", "Нежный", "tener"],
	&"endothermy": ["Теплокровный", "calidus", "Холоднокровный", "frigidus"],
	&"thermal_optimum": ["Жаролюбивый", "thermophilus", "Снежный", "nivalis"],
	&"appendage_size": ["Рогатый", "cornutus", "Безрогий", "mutilus"],
	&"brightness": ["Светлый", "albidus", "Тёмный", "obscurus"],
	&"tail_length": ["Длиннохвостый", "longicauda", "Куцый", "brevicauda"],
}
const SUFFIXES := ["островной", "северный", "южный", "горный", "речной", "поздний", "новый"]
const LATIN_SUFFIXES := ["insularis", "borealis", "australis", "montanus", "fluvialis", "serotinus", "novus"]


## {ru, latin} for a new species of a niche; `g` gives its distinctive trait.
static func generate(niche: StringName, g: Genome, rng: Rng) -> Dictionary:
	var nouns: Array = NOUNS.get(niche, NOUNS[&"other"])
	var noun: String = nouns[rng.range_i(0, nouns.size() - 1)]
	var pick := _distinctive(g, rng)
	var w: Array = TRAIT_WORDS[pick[0]]
	var high: bool = pick[1]
	var adj: String = w[0] if high else w[2]
	var epithet: String = w[1] if high else w[3]
	var genus: String = str(LATIN_GENUS.get(niche, "Vivens")) + str(GENUS_ENDINGS[rng.range_i(0, GENUS_ENDINGS.size() - 1)])
	return {"ru": "%s %s" % [_agree(adj, noun), noun], "latin": "%s %s" % [genus, epithet]}


## Name of a daughter species (speciation): parent noun + a geographic suffix.
static func derive(parent: SpeciesDef, rng: Rng) -> Dictionary:
	var k := rng.range_i(0, SUFFIXES.size() - 1)
	var base := parent.name
	for s in SUFFIXES:
		base = base.trim_suffix(" " + s)
	var latin := parent.latin_name
	if latin == "":
		latin = "Vivens novus"
	var genus: String = latin.split(" ")[0]
	return {"ru": "%s %s" % [base, SUFFIXES[k]], "latin": "%s %s" % [genus, LATIN_SUFFIXES[k]]}


static func _distinctive(g: Genome, rng: Rng) -> Array:
	var best: StringName = &"size"
	var best_d := -1.0
	var high := true
	for id in TRAIT_WORDS:
		var ti := TraitCatalog.index_of(id)
		var d0 := TraitCatalog.normalize(ti, float(TraitCatalog.def_at(ti)["default"]))
		var dev := g.norm_at(ti) - d0 + rng.range_f(-0.02, 0.02)
		if absf(dev) > best_d:
			best_d = absf(dev)
			best = id
			high = dev >= 0.0
	return [best, high]


## Adjective gender agreement for a few feminine/neuter noun endings.
static func _agree(adj: String, noun: String) -> String:
	if noun.ends_with("а") or noun.ends_with("я") or noun.ends_with("ка"):
		if adj.ends_with("ый") or adj.ends_with("ой"):
			return adj.substr(0, adj.length() - 2) + "ая"
		if adj.ends_with("ий"):
			return adj.substr(0, adj.length() - 2) + "яя" if adj.ends_with("ний") else adj.substr(0, adj.length() - 2) + "ая"
	if noun.ends_with("о"):
		if adj.ends_with("ый") or adj.ends_with("ой") or adj.ends_with("ий"):
			return adj.substr(0, adj.length() - 2) + "ое"
	return adj
