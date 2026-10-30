extends SceneTree
const DAY := Units.SECONDS_PER_DAY
func _initialize() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var temp := float(a[0])
	var days := int(a[1])
	var rate := float(a[2])
	var res := float(a[3])
	var w := TestWorlds.flat(temp, 0.5, float(a[4]), 9)
	var climate := TestWorlds.climate_for(w, 0.05)
	climate.sandbox_resource_mult = res
	var plants := EcoDefaults.plants([&"grass"])
	plants.resize(1)
	plants[0].temp_opt = temp
	plants[0].temp_tol = 15.0
	plants[0].moist_opt = 0.5
	plants[0].growth_rate = 0.3
	plants[0].capacity = 1.0
	var eco := EcoGrid.new()
	eco.setup(w, plants, climate)
	var pop := PopulationManager.new()
	var settings := Genetics.settings_with_defaults({"rate": rate})
	pop.setup(w, eco, climate, 5, settings)
	var g := BodyPlanPresets.create(&"grazer")
	g.set_value(&"fur_length", 0.4)
	g.set_value(&"fat_reserve", 0.4)
	g.set_value(&"endothermy", 0.7)
	pop.seed_species(1, g, float(a[6]), PackedInt32Array(), float(a[5]), 8)
	var t0 := Time.get_ticks_msec()
	var traits := [&"fur_length", &"fat_reserve", &"endothermy"]
	for day in days + 1:
		if day % 25 == 0:
			var m := pop.trait_means(1, traits)
			var ex := 0.0
			var n := 0.0
			for p in pop.pools_of(1):
				n += p.count
				ex += p.rates.thermo_w * p.count
			print("d%3d n=%6.1f fur %.3f fat %.3f endo %.3f thermo_w %.1f e %.2f" % [day, n, m[&"fur_length"], m[&"fat_reserve"], m[&"endothermy"], ex / maxf(n, 1e-9), pop.pools_of(1)[0].mean_energy() if n > 0 else 0.0])
		if day == days:
			break
		TestWorlds.advance(climate, DAY)
		eco.step_all(DAY)
		pop.step(DAY)
	print("%.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)
