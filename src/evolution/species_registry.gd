class_name SpeciesRegistry
extends RefCounted
## All species of a world: ids, names, colours, history and extinction.
##   register(def) -> id ; get_species(id) ; all() ; alive()
##   sample_history(day) — uses the providers set by EvolutionSystem so live
##   individuals and population pools are both counted.
## (`get` is Object's native method, hence `get_species`.)

const HISTORY_TRAITS: Array[StringName] = [
	&"size", &"limb_length", &"torso_girth", &"fur_length", &"fat_reserve", &"armor", &"muscle_mass",
	&"metabolism", &"endothermy", &"thermal_optimum", &"water_retention", &"immune", &"clutch_size",
	&"offspring_investment", &"maturity_age", &"diet_preference", &"vigilance", &"brightness",
]
const MAX_HISTORY := 400
const PALETTE := [
	Color(0.90, 0.36, 0.30), Color(0.30, 0.62, 0.90), Color(0.40, 0.78, 0.38), Color(0.95, 0.72, 0.25),
	Color(0.68, 0.45, 0.85), Color(0.25, 0.80, 0.75), Color(0.92, 0.50, 0.70), Color(0.60, 0.60, 0.30),
	Color(0.45, 0.50, 0.95), Color(0.85, 0.55, 0.35), Color(0.55, 0.85, 0.65), Color(0.80, 0.80, 0.80),
]

var species: Dictionary = {}        # id -> SpeciesDef
var next_id: int = 1
## (species_id) -> float — total count (pools + live individuals).
var count_provider: Callable
## (species_id) -> Array[{genome: Genome, weight: float}]
var genome_provider: Callable


func register(def: SpeciesDef, day: float = 0.0) -> int:
	if def.id <= 0 or species.has(def.id):
		def.id = next_id
	next_id = maxi(next_id, def.id + 1)
	if def.ui_color == Color.WHITE:
		var c: Color = PALETTE[(def.id - 1) % PALETTE.size()]
		def.ui_color = c.lightened(0.15 * float(((def.id - 1) / PALETTE.size()) % 3))
	if def.template == null:
		def.template = Genome.new()
	if def.founder == null:
		def.founder = def.template
	if def.name == "":
		def.name = "Вид %d" % def.id
	if def.created_day <= 0.0:
		def.created_day = day
	species[def.id] = def
	EventBus.species_registered.emit(def)
	return def.id


func get_species(id: int) -> SpeciesDef:
	return species.get(id)


func has(id: int) -> bool:
	return species.has(id)


func all() -> Array[SpeciesDef]:
	var out: Array[SpeciesDef] = []
	var ids := species.keys()
	ids.sort()
	for id in ids:
		out.append(species[id])
	return out


func alive() -> Array[SpeciesDef]:
	var out: Array[SpeciesDef] = []
	for d in all():
		if not d.extinct:
			out.append(d)
	return out


func count(id: int) -> float:
	return float(count_provider.call(id)) if count_provider.is_valid() else 0.0


## Marks a species extinct (emits EventBus.species_extinct). Returns true if it changed.
func mark_extinct(id: int, day: float) -> bool:
	var d := get_species(id)
	if d == null or d.extinct:
		return false
	d.extinct = true
	d.extinct_day = day
	EventBus.species_extinct.emit(d)
	return true


## Appends {day, count, traits} to every living species' history.
func sample_history(day: float) -> void:
	for d in alive():
		var n := count(d.id)
		d.peak_count = maxf(d.peak_count, n)
		d.stats["count"] = n
		var means := mean_traits(d.id)
		var entry := {"day": day, "count": snappedf(n, 0.01), "traits": means}
		d.history.append(entry)
		if d.history.size() > MAX_HISTORY:
			# Keep the recent half at full resolution, thin out the old half.
			var thinned := []
			var half := d.history.size() / 2
			for i in d.history.size():
				if i >= half or i % 2 == 0:
					thinned.append(d.history[i])
			d.history = thinned


## Weighted mean normalized values of HISTORY_TRAITS over all members.
func mean_traits(id: int) -> Dictionary:
	var out := {}
	var samples: Array = genome_provider.call(id) if genome_provider.is_valid() else []
	var wsum := 0.0
	for t in HISTORY_TRAITS:
		out[str(t)] = 0.0
	for e in samples:
		var g: Genome = e["genome"]
		var w := float(e["weight"])
		wsum += w
		for t in HISTORY_TRAITS:
			out[str(t)] = float(out[str(t)]) + g.norm(t) * w
	if wsum > 0.0:
		for t in HISTORY_TRAITS:
			out[str(t)] = snappedf(float(out[str(t)]) / wsum, 0.0001)
	return out


func to_dict() -> Dictionary:
	var list := []
	for d in all():
		list.append(d.to_dict())
	return {"next_id": next_id, "species": list}


func from_dict(d: Dictionary) -> void:
	species.clear()
	next_id = Serial.i(d, "next_id", 1)
	for sd in Serial.arr(d, "species"):
		if sd is Dictionary:
			var s := SpeciesDef.from_dict(sd)
			species[s.id] = s
			next_id = maxi(next_id, s.id + 1)
