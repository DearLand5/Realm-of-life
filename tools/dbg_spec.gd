extends SceneTree
const DAY := Units.SECONDS_PER_DAY
func _initialize() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var rate := float(a[0])
	var size := float(a[1])
	var w := TestWorlds.islands(16.0, size, 17)
	var climate := TestWorlds.climate_for(w, 0.05)
	climate.sandbox_resource_mult = 4.0
	var eco := EcoGrid.new()
	eco.setup(w, EcoDefaults.plants([&"grass", &"shrub"]), climate)
	var evo := EvolutionSystem.new()
	evo.settings = Genetics.settings_with_defaults({"rate": rate})
	var pop := PopulationManager.new()
	pop.setup(w, eco, climate, 5, evo.settings)
	evo.attach_population(pop)
	var d := SpeciesDef.new()
	d.name = "Worm"
	d.template = BodyPlanPresets.create(&"insect")
	evo.registry.register(d)
	evo.speciation_threshold = float(a[2])
	evo.speciation_min_days = 5.0
	pop.seed_species(d.id, d.template, 16.0, PackedInt32Array(), 0.0, 1)
	var t0 := Time.get_ticks_msec()
	for day in int(a[3]):
		TestWorlds.advance(climate, DAY)
		eco.step_all(DAY)
		pop.step(DAY)
		evo.daily(float(day + 1))
		if day % 10 == 0:
			var demes := pop.demes(d.id)
			var line := "d%d n=%.0f demes %d" % [day, pop.total_count(d.id), demes.size()]
			if demes.size() >= 2:
				demes.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["count"]) > float(y["count"]))
				var c0 := Phylogeny.centroid(demes[0]["samples"])
				for k in range(1, demes.size()):
					line += " | deme%d n=%.1f dist %.3f" % [k, float(demes[k]["count"]), Genetics.distance(Phylogeny.centroid(demes[k]["samples"]), c0)]
			print(line)
			var occ := ""
			for sec in pop.sectors:
				if sec.pools.has(d.id):
					occ += " %d:%.1f(l%.2f)" % [sec.index, (sec.pools[d.id] as SpeciesPool).count, sec.land_frac]
			print("   ", occ)
	for e in evo.log_entries:
		print("  [d%d] %s" % [int(e["day"]), e["text"]])
	print("%.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)
