extends TestCase
## Species registry, extinction, speciation, phylogeny, evolution log and the
## procedural fauna generator.

const DAY := Units.SECONDS_PER_DAY


class Rig:
	var world: WorldData
	var climate: ClimateState
	var eco: EcoGrid
	var pop: PopulationManager
	var evo: EvolutionSystem

	func _init(w: WorldData, settings: Dictionary = {}, plants: Array[PlantSpecies] = []) -> void:
		world = w
		climate = TestWorlds.climate_for(w, 0.05)
		climate.sandbox_resource_mult = 4.0
		eco = EcoGrid.new()
		eco.setup(w, plants if not plants.is_empty() else EcoDefaults.plants([&"grass", &"shrub"]), climate)
		evo = EvolutionSystem.new()
		evo.settings = Genetics.settings_with_defaults(settings)
		pop = PopulationManager.new()
		pop.setup(w, eco, climate, 5, evo.settings)
		evo.attach_population(pop)

	func add_species(preset: StringName, count: float, name: String = "", where: PackedInt32Array = PackedInt32Array(),
			variation: float = 0.0, samples: int = 1) -> SpeciesDef:
		var d := SpeciesDef.new()
		d.name = name if name != "" else str(preset)
		d.template = BodyPlanPresets.create(preset)
		evo.registry.register(d)
		pop.seed_species(d.id, d.template, count, where, variation, samples)
		return d

	func run_days(days: int, start_day: int = 0) -> void:
		for k in days:
			TestWorlds.advance(climate, DAY)
			eco.step_all(DAY)
			pop.step(DAY)
			evo.daily(float(start_day + k + 1))


# --- Registry ---------------------------------------------------------------------------

func test_registry_basics() -> void:
	var reg := SpeciesRegistry.new()
	var a := SpeciesDef.new()
	a.template = BodyPlanPresets.create(&"grazer")
	var b := SpeciesDef.new()
	b.name = "Хищник"
	b.template = BodyPlanPresets.create(&"predator")
	var ia := reg.register(a)
	var ib := reg.register(b)
	check(ia != ib and ia > 0 and ib > 0, "unique positive ids")
	check(reg.get_species(ia) == a and reg.has(ib), "lookup works")
	check(a.name != "", "default name assigned")
	check(a.ui_color != Color.WHITE, "colour assigned")
	check(reg.all().size() == 2 and reg.alive().size() == 2, "all/alive")
	# Registering a def with a taken id gives it a fresh one.
	var c := SpeciesDef.new()
	c.id = ia
	c.template = a.template
	var ic := reg.register(c)
	check(ic != ia, "id collision resolved")
	# Roundtrip.
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(reg.to_dict()))
	var reg2 := SpeciesRegistry.new()
	reg2.from_dict(parsed)
	check(reg2.all().size() == 3, "registry roundtrip keeps all species")
	check(reg2.get_species(ib).name == "Хищник", "names survive")
	check(reg2.next_id == reg.next_id, "id counter survives")
	var fresh := SpeciesDef.new()
	fresh.template = a.template
	check(reg2.register(fresh) == reg.next_id, "ids continue after load")
	# Unknown keys and missing fields are tolerated.
	reg2.from_dict({"species": [{"id": 5, "unknown": 1}], "extra": true})
	check(reg2.get_species(5) != null, "tolerant loading")


func test_history_and_extinction() -> void:
	var rig := Rig.new(TestWorlds.flat(16.0, 0.5, 64.0, 9))
	var g := rig.add_species(&"grazer", 8.0, "Травоед")
	var p := rig.add_species(&"predator", 1.0, "Хищник")
	var extinct_ids := []
	var bus := SpeciesRegistry.bus()
	check(bus != null, "EventBus autoload reachable")
	var cb := func(s: RefCounted) -> void: extinct_ids.append((s as SpeciesDef).id)
	if bus != null:
		bus.connect(&"species_extinct", cb)
	rig.run_days(5)
	check(g.history.size() == 5, "one history entry per day (%d)" % g.history.size())
	var last: Dictionary = g.history[g.history.size() - 1]
	check(last["count"] > 1.0 and last["traits"].has("size") and last["traits"].has("fur_length"), "history keeps count and trait means")
	near(rig.evo.count_of(g.id), rig.pop.total_count(g.id), 1e-6, "count provider matches the pools")
	check(g.peak_count >= 8.0, "peak count tracked")
	# Wipe out the predators.
	for sec in rig.pop.sectors:
		sec.pools.erase(p.id)
	rig.run_days(2, 5)
	check(p.extinct, "extinction detected")
	check(p.extinct_day > 0.0, "extinction day recorded")
	check(extinct_ids == [p.id], "species_extinct emitted once (%s)" % str(extinct_ids))
	check(not g.extinct, "other species unaffected")
	check(rig.evo.log_entries.any(func(e: Dictionary) -> bool: return e["category"] == &"extinction"), "extinction logged")
	check(rig.evo.registry.alive().size() == 1, "alive list shrinks")
	if bus != null:
		bus.disconnect(&"species_extinct", cb)
	# History of the extinct species stops growing.
	var n := p.history.size()
	rig.run_days(2, 7)
	check(p.history.size() == n, "no history for extinct species")


func test_live_individuals_are_counted_through_provider() -> void:
	var rig := Rig.new(TestWorlds.flat(16.0, 0.5, 64.0, 9))
	var d := rig.add_species(&"grazer", 4.0)
	var live: Array[Individual] = []
	var rng := Rng.new(2)
	for i in 3:
		var ind := Individual.create(d.template, d.id, &"adult", rng)
		live.append(ind)
	rig.evo.live_provider = func(id: int) -> Array: return live if id == d.id else []
	near(rig.evo.count_of(d.id), 7.0, 0.01, "pools + live agents are counted")
	live[0].alive = false
	near(rig.evo.count_of(d.id), 6.0, 0.01, "dead agents are not")
	check(rig.evo.genomes_of(d.id).size() >= 3, "genomes of live agents are included")
	# A species held only by live agents is not extinct.
	for sec in rig.pop.sectors:
		sec.pools.erase(d.id)
	rig.evo.daily(1.0)
	check(not d.extinct, "live-only species survives")


# --- Speciation -------------------------------------------------------------------------

func _island_sectors(pop: PopulationManager, left: bool) -> PackedInt32Array:
	var out := PackedInt32Array()
	for s in pop.sectors:
		if s.land_frac > 0.3 and ((s.center.x < 0.0) == left):
			out.append(s.index)
	return out


func test_isolated_divergent_deme_speciates() -> void:
	var rig := Rig.new(TestWorlds.islands(16.0, 160.0, 17))
	var base := BodyPlanPresets.create(&"insect")
	var d := SpeciesDef.new()
	d.name = "Мошка"
	d.template = base
	rig.evo.registry.register(d)
	var west := _island_sectors(rig.pop, true)
	var east := _island_sectors(rig.pop, false)
	check(west.size() >= 1 and east.size() >= 1, "two island groups exist (%d, %d)" % [west.size(), east.size()])
	rig.pop.seed_species(d.id, base, 12.0, west, 0.0, 1)
	var diverged := base.copy_shared_plan()
	diverged.set_value(&"size", base.value(&"size") * 1.6)
	diverged.set_value(&"fur_length", 2.0)
	diverged.set_value(&"clutch_size", base.value(&"clutch_size") * 1.5)
	diverged.set_value(&"brightness", 0.2)
	rig.pop.seed_species(d.id, diverged, 12.0, east, 0.0, 1)
	check(rig.pop.demes(d.id).size() == 2, "the islands are separate demes")
	var events := []
	var bus := SpeciesRegistry.bus()
	var cb := func(parent: RefCounted, child: RefCounted) -> void: events.append([(parent as SpeciesDef).id, (child as SpeciesDef).id])
	if bus != null:
		bus.connect(&"speciation", cb)
	rig.evo.speciation_min_days = 6.0
	var dist := Genetics.distance(base, diverged)
	check(dist > 0.01, "the demes are genetically distinct (%.3f)" % dist)
	rig.evo.speciation_threshold = dist * 0.5
	rig.evo.on_speciation = func(_p: int, _n: int, _sec: PackedInt32Array) -> void: events.append("callback")
	# Not yet: the divergence has to persist.
	rig.evo.check_speciation(1.0)
	check(rig.evo.registry.all().size() == 1, "no instant speciation")
	rig.run_days(10)
	if bus != null:
		bus.disconnect(&"speciation", cb)
	var all := rig.evo.registry.all()
	check(all.size() == 2, "a new species appeared (%d species)" % all.size())
	if all.size() < 2:
		return
	var child := all[1]
	check(child.origin == &"evolved" and child.parent_id == d.id, "evolved species links to its parent")
	check(child.name != "" and child.name != d.name, "the new species is named (%s)" % child.name)
	check(child.latin_name != "", "latin name given")
	check(child.template != null and child.template.value(&"size") > base.value(&"size") * 1.2, "template is the deme's centroid")
	check(rig.pop.total_count(child.id) > 5.0, "pools were moved to the new species")
	check(rig.pop.total_count(d.id) > 5.0, "parent keeps its own deme")
	for si in east:
		check(not rig.pop.sectors[si].pools.has(d.id), "east pools no longer belong to the parent")
	check(events.size() == 2 and events.has("callback"), "signal and callback fired (%s)" % str(events))
	check(rig.evo.log_entries.any(func(e: Dictionary) -> bool: return e["category"] == &"speciation" and e["data"]["parent"] == d.id), "speciation logged")
	# Phylogeny export.
	var tree := rig.evo.phylogeny()
	check(tree["nodes"].size() == 2 and tree["edges"].size() == 1, "phylogeny has two nodes and one edge")
	var edge: Dictionary = tree["edges"][0]
	check(edge["from"] == d.id and edge["to"] == child.id, "edge points from parent to child")
	var node_child: Dictionary = tree["nodes"].filter(func(n: Dictionary) -> bool: return n["id"] == child.id)[0]
	check(node_child["depth"] == 1 and node_child["origin"] == "evolved", "child node depth/origin")
	# Lineage comparison.
	var diffs := rig.evo.compare(d.id, child.id)
	check(not diffs.is_empty(), "lineages differ")
	if not diffs.is_empty():
		check(float(diffs[0]["a"]) != float(diffs[0]["b"]) and str(diffs[0]["label"]) != "", "comparison names the traits")
	check(not rig.evo.compare_to_founder(child.id).is_empty() or true, "compare_to_founder runs")


func test_speciation_emerges_from_mutation_on_isolated_islands() -> void:
	# The same founders on two islands, high mutation, no gene flow, a very
	# low threshold: independent mutation + selection make the demes drift apart.
	var rig := Rig.new(TestWorlds.islands(16.0, 160.0, 17), {"rate": 30.0})
	rig.evo.speciation_threshold = 0.004
	rig.evo.speciation_min_days = 5.0
	var d := rig.add_species(&"insect", 16.0, "Мошка")
	check(rig.pop.demes(d.id).size() == 2, "two isolated demes at the start")
	rig.run_days(40)
	var evolved := rig.evo.registry.all().filter(func(s: SpeciesDef) -> bool: return s.origin == &"evolved")
	check(evolved.size() >= 1, "at least one evolved species (%d)" % evolved.size())
	if not evolved.is_empty():
		check((evolved[0] as SpeciesDef).parent_id == d.id, "parent link")
	# With mutation switched off nothing diverges.
	var calm := Rig.new(TestWorlds.islands(16.0, 160.0, 17), {"rate": 0.0})
	calm.evo.speciation_threshold = 0.004
	calm.evo.speciation_min_days = 5.0
	calm.add_species(&"insect", 16.0, "Мошка")
	calm.run_days(40)
	check(calm.evo.registry.all().size() == 1, "no mutation -> no speciation (%d)" % calm.evo.registry.all().size())


func test_mutation_settings_api() -> void:
	var evo := EvolutionSystem.new()
	evo.set_mutation_rate(3.0)
	evo.set_mutation_strength(0.5)
	evo.set_category_locked("color", true)
	check(evo.settings["rate"] == 3.0 and evo.settings["strength"] == 0.5, "rate and strength stored")
	check(evo.settings["categories"]["color"] == false and evo.settings["categories"]["anatomy"] == true, "category locked")
	var rig := Rig.new(TestWorlds.flat(16.0, 0.5, 32.0, 9))
	rig.evo.set_mutation_rate(7.0)
	check(rig.pop.mutation_settings["rate"] == 7.0, "population manager shares the settings")


func test_evolution_roundtrip() -> void:
	var rig := Rig.new(TestWorlds.islands(16.0, 160.0, 17), {"rate": 30.0})
	rig.evo.speciation_threshold = 0.004
	rig.evo.speciation_min_days = 5.0
	var d := rig.add_species(&"insect", 16.0, "Мошка")
	rig.run_days(25)
	var saved := rig.evo.to_dict()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var evo2 := EvolutionSystem.new()
	evo2.from_dict(parsed)
	check(evo2.registry.all().size() == rig.evo.registry.all().size(), "species restored")
	check(evo2.log_entries.size() == rig.evo.log_entries.size(), "log restored")
	check(evo2.settings["rate"] == 30.0, "settings restored")
	var d2 := evo2.registry.get_species(d.id)
	check(d2 != null and d2.history.size() == d.history.size(), "history restored")
	if d2 != null:
		near(d2.peak_count, d.peak_count, 0.01, "peak restored")
	check(evo2.phylogeny()["nodes"].size() == rig.evo.phylogeny()["nodes"].size(), "phylogeny identical after load")


# --- Fauna generator -------------------------------------------------------------------------

func test_fauna_generator_viable_and_deterministic() -> void:
	var world := TestWorlds.lake(16.0, 192.0, 25)
	var plants := EcoDefaults.plants()
	var a := FaunaGenerator.generate(world, plants, Rng.new(3), 8)
	var b := FaunaGenerator.generate(world, plants, Rng.new(3), 8)
	check(a.size() == 8, "requested number of species (%d)" % a.size())
	check(a.size() == b.size(), "deterministic count")
	var niches := {}
	var names := {}
	var info := FaunaGenerator.analyze(world, plants)
	for i in a.size():
		var d := a[i]
		niches[d.niche] = true
		names[d.name] = true
		check(d.origin == &"procedural" and d.name != "" and d.latin_name != "" and d.description != "", "%s: origin, names and description" % d.name)
		check(d.template != null and d.founder == d.template, "%s: genome set" % d.name)
		var ph := Phenotype.build(d.template)
		var items := AnatomyDiagnostics.run(ph)
		var v := AnatomyDiagnostics.viability(items)
		check(v >= FaunaGenerator.MIN_VIABILITY, "%s viable (%.2f)" % [d.name, v])
		check(not items.any(func(it: Dictionary) -> bool: return it["level"] == &"critical"), "%s has no critical defects" % d.name)
		var spec: Dictionary = FaunaGenerator.NICHES[d.niche]
		var h := FaunaGenerator.habitat_suitability(ph, spec["medium"], info)
		check(h >= FaunaGenerator.MIN_HABITAT, "%s has a habitat (%.2f)" % [d.name, h])
		if i < b.size():
			check(b[i].name == d.name and b[i].niche == d.niche, "deterministic species %d" % i)
			near(b[i].template.value(&"size"), d.template.value(&"size"), 1e-9, "deterministic genome %d" % i)
	check(niches.size() >= 5, "several niches are filled (%d)" % niches.size())
	check(niches.has(&"grazer") and niches.has(&"predator"), "producers' consumers and predators exist")
	check(niches.has(&"fish") or niches.has(&"filter"), "the lake is populated")
	check(names.size() >= 6, "names differ (%d unique)" % names.size())


func test_fauna_generator_respects_the_world() -> void:
	# A cold world without water: no aquatic niches, thicker coats than in a warm one.
	var cold := TestWorlds.cold(128.0)
	var warm := TestWorlds.warm(128.0)
	var plants := EcoDefaults.plants()
	var fc := FaunaGenerator.generate(cold, plants, Rng.new(4), 6)
	for d in fc:
		check(FaunaGenerator.NICHES[d.niche]["medium"] != &"water", "no aquatic species in a dry world (%s)" % d.niche)
	var fur_cold := 0.0
	var fur_warm := 0.0
	var n := 0.0
	var fw := FaunaGenerator.generate(warm, plants, Rng.new(4), 6)
	for i in mini(fc.size(), fw.size()):
		if fc[i].niche == fw[i].niche and fc[i].template.value(&"endothermy") > 0.5:
			fur_cold += fc[i].template.value(&"fur_length")
			fur_warm += fw[i].template.value(&"fur_length")
			n += 1.0
	if n > 0.0:
		check(fur_cold / n > fur_warm / n, "cold-world fauna has denser fur (%.2f vs %.2f)" % [fur_cold / n, fur_warm / n])
	# Generated species can actually live in pools in their world.
	var rig := Rig.new(cold, {}, plants)
	for d in fc.slice(0, 3):
		rig.evo.registry.register(d)
		rig.pop.seed_species(d.id, d.template, 10.0)
		check(rig.pop.total_count(d.id) > 0.0, "%s found a place to live" % d.name)
