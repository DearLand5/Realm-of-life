class_name EvolutionSystem
extends RefCounted
## World-level evolution bookkeeping:
##   * mutation settings (`settings`, see Genetics.DEFAULT_SETTINGS) shared
##     with PopulationManager and BiologySystem;
##   * daily(day): history sampling, extinction detection, speciation
##     detection, notable trait shifts → `log_entries`;
##   * speciation: a deme (connected group of sectors) whose centroid genome
##     stays ≥ speciation_threshold away from the species' main deme for
##     speciation_min_days becomes a new SpeciesDef (origin &"evolved");
##   * phylogeny() export and lineage comparisons.
## Counts come from providers so live agents and pools are both included.

const MAX_LOG := 500
const MIN_DEME := 5.0
const SHIFT_STEP := 0.1                 # normalized trait shift that gets logged

var registry := SpeciesRegistry.new()
var settings: Dictionary = Genetics.settings_with_defaults()
## [{day, category: &"speciation"|&"extinction"|&"mutation"|&"species", text, data}]
var log_entries: Array = []
var speciation_threshold: float = 0.1
var speciation_min_days: float = 8.0
var rng := Rng.new(424242)
var pop: PopulationManager
## (species_id) -> Array[Individual] — live (tier A/B) members, optional.
var live_provider: Callable
## (parent_id, new_id, sectors: PackedInt32Array) — lets the world retag live agents.
var on_speciation: Callable
var _isolation := {}
var _shift_logged := {}
var _seen := {}


func _init() -> void:
	registry.count_provider = count_of
	registry.genome_provider = genomes_of


func attach_population(p: PopulationManager, live: Callable = Callable()) -> void:
	pop = p
	live_provider = live
	p.mutation_settings = settings


# --- Settings ------------------------------------------------------------------------

func set_mutation_rate(rate: float) -> void:
	settings["rate"] = maxf(rate, 0.0)


func set_mutation_strength(strength: float) -> void:
	settings["strength"] = maxf(strength, 0.0)


## Locks/unlocks a mutation category (anatomy, color, physiology, life, behavior, senses, structure).
func set_category_locked(category: String, locked: bool) -> void:
	(settings["categories"] as Dictionary)[category] = not locked


# --- Providers ----------------------------------------------------------------------

func _live(id: int) -> Array:
	return live_provider.call(id) if live_provider.is_valid() else []


func count_of(id: int) -> float:
	var n := pop.total_count(id) if pop != null else 0.0
	for ind in _live(id):
		if (ind as Individual).alive:
			n += 1.0
	return n


func genomes_of(id: int) -> Array:
	var out: Array = pop.genome_samples(id) if pop != null else []
	for ind in _live(id):
		var i := ind as Individual
		if i.alive:
			out.append({"genome": i.genome, "weight": 1.0})
	return out


# --- Daily bookkeeping --------------------------------------------------------------

func daily(day: float) -> void:
	registry.sample_history(day)
	check_extinctions(day)
	check_speciation(day)
	check_trait_shifts(day)


func check_extinctions(day: float) -> Array[SpeciesDef]:
	var out: Array[SpeciesDef] = []
	for d in registry.alive():
		var n := count_of(d.id)
		if n >= 1.0:
			_seen[d.id] = true
		elif n < 0.5 and _seen.has(d.id):
			if registry.mark_extinct(d.id, day):
				if pop != null:
					pop.remove_species(d.id)  # last fractions of an individual
				add_log(day, &"extinction", "Вид «%s» вымер (существовал %.0f сут)." % [d.name, day - d.created_day], {"species": d.id})
				out.append(d)
	return out


func check_speciation(day: float) -> Array[SpeciesDef]:
	var out: Array[SpeciesDef] = []
	if pop == null:
		return out
	for d in registry.alive():
		var demes := pop.demes(d.id)
		if demes.size() < 2:
			_clear_isolation(d.id)
			continue
		demes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["count"]) > float(b["count"]))
		var main := Phylogeny.centroid(demes[0]["samples"])
		for k in range(1, demes.size()):
			var dm: Dictionary = demes[k]
			if float(dm["count"]) < MIN_DEME:
				continue
			var c := Phylogeny.centroid(dm["samples"])
			var dist := Genetics.distance(c, main)
			var sec: PackedInt32Array = dm["sectors"]
			var anchor := sec[0]
			for si in sec:
				anchor = mini(anchor, si)
			var key := "%d:%d" % [d.id, anchor]
			if dist < speciation_threshold:
				_isolation.erase(key)
				continue
			if not _isolation.has(key):
				_isolation[key] = day
			elif day - float(_isolation[key]) >= speciation_min_days:
				_isolation.erase(key)
				out.append(_speciate(d, dm, c, dist, day))
	return out


func _clear_isolation(id: int) -> void:
	var prefix := "%d:" % id
	for k in _isolation.keys():
		if str(k).begins_with(prefix):
			_isolation.erase(k)


func _speciate(parent: SpeciesDef, deme: Dictionary, centroid: Genome, dist: float, day: float) -> SpeciesDef:
	var nd := SpeciesDef.new()
	var names := SpeciesNamer.derive(parent, rng)
	nd.name = names["ru"]
	nd.latin_name = names["latin"]
	nd.origin = &"evolved"
	nd.parent_id = parent.id
	nd.template = centroid
	nd.founder = centroid
	nd.niche = parent.niche
	nd.description = "Обособился от вида «%s» после изоляции: генетическая дистанция %.2f." % [parent.name, dist]
	registry.register(nd, day)
	var sectors: PackedInt32Array = deme["sectors"]
	pop.reassign_species(sectors, parent.id, nd.id)
	if on_speciation.is_valid():
		on_speciation.call(parent.id, nd.id, sectors)
	var diffs := Phylogeny.compare_genomes(parent.template, centroid, 3)
	var labels := PackedStringArray()
	for e in diffs:
		labels.append(str(e["label"]))
	add_log(day, &"speciation", "Новый вид «%s» произошёл от «%s» (отличия: %s)." % [nd.name, parent.name, ", ".join(labels)],
		{"species": nd.id, "parent": parent.id, "distance": dist})
	var b := SpeciesRegistry.bus()
	if b != null:
		b.emit_signal(&"speciation", parent, nd)
	return nd


## Logs sustained shifts of mean trait values away from the founder.
func check_trait_shifts(day: float) -> void:
	for d in registry.alive():
		if d.history.is_empty() or d.founder == null:
			continue
		var means: Dictionary = d.history[d.history.size() - 1]["traits"]
		for t in SpeciesRegistry.HISTORY_TRAITS:
			var now := float(means.get(str(t), 0.0))
			var base := d.founder.norm(t)
			var steps := int((now - base) / SHIFT_STEP)
			var key := "%d:%s" % [d.id, t]
			var logged := int(_shift_logged.get(key, 0))
			if steps != 0 and (absi(steps) > absi(logged) or signi(steps) != signi(logged)):
				_shift_logged[key] = steps
				var td := TraitCatalog.get_def(t)
				var ti := TraitCatalog.index_of(t)
				add_log(day, &"mutation", "У вида «%s» сдвигается признак «%s»: %.2f → %.2f." % [d.name, td["label"],
					TraitCatalog.denormalize(ti, base), TraitCatalog.denormalize(ti, now)], {"species": d.id, "trait": t})


func add_log(day: float, category: StringName, text: String, data: Dictionary = {}) -> void:
	var e := {"time": day * Units.SECONDS_PER_DAY, "day": day, "category": category, "text": text, "data": data}
	log_entries.append(e)
	while log_entries.size() > MAX_LOG:
		log_entries.pop_front()
	var b := SpeciesRegistry.bus()
	if b != null:
		b.emit_signal(&"sim_event_logged", e)


# --- Phylogeny & comparison ----------------------------------------------------------

func phylogeny() -> Dictionary:
	return Phylogeny.export(registry)


## Current centroid genome of a species (pools + live), or its template.
func current_genome(id: int) -> Genome:
	var c := Phylogeny.centroid(genomes_of(id))
	if c != null:
		return c
	var d := registry.get_species(id)
	return d.template if d != null else null


func compare(a_id: int, b_id: int) -> Array:
	var a := current_genome(a_id)
	var b := current_genome(b_id)
	return Phylogeny.compare_genomes(a, b) if a != null and b != null else []


## Founder vs current population of one species.
func compare_to_founder(id: int) -> Array:
	var d := registry.get_species(id)
	var now := current_genome(id)
	return Phylogeny.compare_genomes(d.founder, now) if d != null and now != null else []


# --- Save / load ---------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"registry": registry.to_dict(), "settings": settings.duplicate(true), "log": log_entries.duplicate(true),
		"speciation_threshold": speciation_threshold, "speciation_min_days": speciation_min_days,
		"isolation": _isolation.duplicate(), "shifts": _shift_logged.duplicate(), "seen": _seen.keys(),
		"rng": rng.get_state(),
	}


func from_dict(d: Dictionary) -> void:
	registry.from_dict(Serial.dict(d, "registry"))
	settings = Genetics.settings_with_defaults(Serial.dict(d, "settings"))
	if pop != null:
		pop.mutation_settings = settings
	log_entries = Serial.arr(d, "log").duplicate(true)
	speciation_threshold = Serial.f(d, "speciation_threshold", speciation_threshold)
	speciation_min_days = Serial.f(d, "speciation_min_days", speciation_min_days)
	_isolation = Serial.dict(d, "isolation").duplicate()
	_shift_logged = Serial.dict(d, "shifts").duplicate()
	_seen.clear()
	for id in Serial.arr(d, "seen"):
		_seen[int(id)] = true
	var st = d.get("rng", null)
	if st is float or st is int:
		rng.set_state(int(st))
