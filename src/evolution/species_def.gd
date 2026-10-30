class_name SpeciesDef
extends RefCounted
## A species known to the world: player-designed, procedurally generated or
## evolved by speciation. `template` is the reference genome (founder or the
## current centroid); individuals carry their own genomes.

var id: int = 0
var name: String = ""
var origin: StringName = &"player"     # player | procedural | evolved
var parent_id: int = -1                # ancestor species (phylogeny)
var template: Genome
var ui_color := Color.WHITE
var created_day: float = 0.0
var extinct := false
var extinct_day: float = -1.0
var library_uid: String = ""           # link to SpeciesLibrary entry
var niche: StringName = &""            # descriptive: grazer, predator, filter...
var description: String = ""
## [{day: float, count: int, traits: {trait_id: mean_norm}}], capped
var history: Array = []
var stats: Dictionary = {}             # live aggregates (count, mean_age...) — not saved
# --- Additive extensions (biosim) -------------------------------------------------
var latin_name: String = ""            # pseudo-Latin binomial
## Founder genome kept unchanged (template may later track the current centroid).
var founder: Genome
var peak_count: float = 0.0            # largest population ever observed


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "origin": str(origin), "parent_id": parent_id,
		"template": template.to_dict() if template != null else {}, "ui_color": Serial.color(ui_color),
		"created_day": created_day, "extinct": extinct, "extinct_day": extinct_day,
		"library_uid": library_uid, "niche": str(niche), "description": description,
		"history": history.duplicate(true),
		"latin_name": latin_name, "founder": founder.to_dict() if founder != null and founder != template else {},
		"peak_count": peak_count,
	}


static func from_dict(d: Dictionary) -> SpeciesDef:
	var s := SpeciesDef.new()
	s.id = Serial.i(d, "id", 0)
	s.name = Serial.s(d, "name", "Вид")
	s.origin = Serial.sn(d, "origin", &"player")
	s.parent_id = Serial.i(d, "parent_id", -1)
	var td := Serial.dict(d, "template")
	s.template = Genome.from_dict(td) if not td.is_empty() else Genome.new()
	s.ui_color = Serial.to_color(d.get("ui_color"), Color.WHITE)
	s.created_day = Serial.f(d, "created_day", 0.0)
	s.extinct = Serial.b(d, "extinct", false)
	s.extinct_day = Serial.f(d, "extinct_day", -1.0)
	s.library_uid = Serial.s(d, "library_uid", "")
	s.niche = Serial.sn(d, "niche", &"")
	s.description = Serial.s(d, "description", "")
	s.history = Serial.arr(d, "history").duplicate(true)
	s.latin_name = Serial.s(d, "latin_name", "")
	var fd := Serial.dict(d, "founder")
	s.founder = Genome.from_dict(fd) if not fd.is_empty() else s.template
	s.peak_count = Serial.f(d, "peak_count", 0.0)
	return s
