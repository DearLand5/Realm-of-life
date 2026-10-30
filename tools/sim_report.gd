extends SceneTree
## Headless ecosystem report: runs a synthetic world in population mode at a
## large time step and prints a compact time series (populations per
## species, plant biomass, mean traits, events).
##   godot --headless --path . -s tools/sim_report.gd -- [options]
## Options (all optional):
##   --days N         simulated days (default 100)
##   --dt S           biological seconds per step (default 21600 = 6 h)
##   --every N        print every N days (default 5)
##   --world W        flat | cold | warm | hot | lake | islands | grass (default grass)
##   --temp C         flat land with this annual mean temperature (overrides --world)
##   --size M         world size in metres (default 256)
##   --species LIST   comma list of BodyPlanPresets ids (default grazer,predator,insect,worm)
##   --fauna N        use FaunaGenerator with N species instead of --species
##   --count N        founders per species (default 60)
##   --counts LIST    comma list of founders per species (overrides --count by index)
##   --forms LIST     plant forms to include (default all), e.g. grass,shrub
##   --set LIST       founder trait overrides, e.g. fur_length=0.4,fat_reserve=0.4
##   --resource R     plant growth multiplier (ClimateState.sandbox_resource_mult)
##   --seed S         RNG seed (default 7)
##   --rate R         mutation rate multiplier (default 1)
##   --traits LIST    traits to print means of (default size,fur_length,fat_reserve,endothermy)

const DAY := Units.SECONDS_PER_DAY


func _initialize() -> void:
	await process_frame
	var opt := _parse(OS.get_cmdline_user_args())
	var size := float(opt.get("size", "256"))
	var w := TestWorlds.flat(float(opt["temp"]), 0.5, size) if opt.has("temp") else _world(str(opt.get("world", "grass")), size)
	var climate := TestWorlds.climate_for(w, 0.05)
	climate.sandbox_resource_mult = float(opt.get("resource", "1"))
	var plants := EcoDefaults.plants(str(opt.get("forms", "")).split(",", false) if opt.has("forms") else [])
	var eco := EcoGrid.new()
	eco.setup(w, plants, climate)
	var seed_value := int(opt.get("seed", "7"))
	var evo := EvolutionSystem.new()
	evo.settings = Genetics.settings_with_defaults({"rate": float(opt.get("rate", "1"))})
	var reg := evo.registry
	var pop := PopulationManager.new()
	pop.setup(w, eco, climate, seed_value, evo.settings)
	evo.attach_population(pop)
	var count := float(opt.get("count", "60"))
	var defs: Array[SpeciesDef] = []
	if opt.has("fauna"):
		defs = FaunaGenerator.generate(w, plants, Rng.new(seed_value), int(opt["fauna"]))
	else:
		for id in str(opt.get("species", "grazer,predator,insect,worm")).split(","):
			var d := SpeciesDef.new()
			d.name = BodyPlanPresets.label(StringName(id))
			d.template = BodyPlanPresets.create(StringName(id))
			d.origin = &"player"
			defs.append(d)
	var counts: PackedStringArray = str(opt.get("counts", "")).split(",", false)
	for d0 in defs:
		for kv in str(opt.get("set", "")).split(",", false):
			var parts := kv.split("=")
			d0.template.set_value(StringName(parts[0]), float(parts[1]))
	for i in defs.size():
		var d := defs[i]
		reg.register(d)
		pop.seed_species(d.id, d.template, float(counts[i]) if i < counts.size() else count)
	var traits: Array = []
	for t in str(opt.get("traits", "size,fur_length,fat_reserve,endothermy")).split(","):
		traits.append(StringName(t))
	var days := int(opt.get("days", "100"))
	var dt := float(opt.get("dt", "21600"))
	var every := int(opt.get("every", "5"))
	var steps_per_day := maxi(1, int(round(DAY / dt)))
	_header(defs, plants)
	var t0 := Time.get_ticks_msec()
	for day in days + 1:
		if day % every == 0:
			_row(day, climate, eco, pop, defs, traits)
		if day == days:
			break
		for k in steps_per_day:
			TestWorlds.advance(climate, dt)
			eco.step_all(dt)
			pop.step(dt)
		evo.daily(float(day + 1))
	print("— %.1f s real time, %d log entries" % [(Time.get_ticks_msec() - t0) / 1000.0, evo.log_entries.size()])
	for e in evo.log_entries.slice(maxi(0, evo.log_entries.size() - 12)):
		print("  [day %d] %s" % [int(e["day"]), e["text"]])
	quit(0)


func _parse(args: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < args.size():
		var a := args[i]
		if a.begins_with("--") and i + 1 < args.size():
			out[a.substr(2)] = args[i + 1]
			i += 2
		else:
			i += 1
	return out


func _world(name: String, size: float) -> WorldData:
	match name:
		"flat":
			return TestWorlds.flat(15.0, 0.55, size)
		"cold":
			return TestWorlds.cold(size)
		"warm":
			return TestWorlds.warm(size)
		"hot":
			return TestWorlds.hot_dry(size)
		"lake":
			return TestWorlds.lake(16.0, size)
		"islands":
			return TestWorlds.islands(16.0, size)
	return TestWorlds.flat(16.0, 0.38, size)


func _header(defs: Array[SpeciesDef], plants: Array[PlantSpecies]) -> void:
	var names := PackedStringArray()
	for d in defs:
		names.append("%d=%s" % [d.id, d.name])
	print("species: ", ", ".join(names))
	var pn := PackedStringArray()
	for p in plants:
		pn.append(p.name.substr(0, 5))
	print("plants (t): ", ", ".join(pn))


func _row(day: int, climate: ClimateState, eco: EcoGrid, pop: PopulationManager, defs: Array[SpeciesDef], traits: Array) -> void:
	var counts := pop.species_counts()
	var parts := PackedStringArray()
	for d in defs:
		var c := float(counts.get(d.id, 0.0))
		var e := 0.0
		var n := 0.0
		for p in pop.pools_of(d.id):
			e += p.mean_energy() * p.count
			n += p.count
		parts.append("%d:%6.1f(e%.2f)" % [d.id, c, e / maxf(n, 1e-9)])
	var bio := PackedStringArray()
	for p in eco.plant_species.size():
		bio.append("%.0f" % (eco.total_biomass(p) / 1000.0))
	print("d%3d %s T%5.1f | %s | plants %s | carc %.0fkg" % [day, Units.SEASON_NAMES[climate.season].substr(0, 3), climate.seasonal_offset(), "  ".join(parts), "/".join(bio), eco.carcasses.total_kg()])
	if day % 25 == 0:
		for d in defs:
			var m := pop.trait_means(d.id, traits)
			if pop.total_count(d.id) <= 0.0:
				continue
			var tp := PackedStringArray()
			for t in traits:
				tp.append("%s=%.3f" % [t, float(m.get(t, 0.0))])
			print("      %d traits: %s" % [d.id, " ".join(tp)])
