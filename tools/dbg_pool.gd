extends SceneTree
## Debug: species in a small world, prints per-species aggregates and rate components.
## args: species_list size days count dt every
const DAY := Units.SECONDS_PER_DAY

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var presets := (args[0] if args.size() > 0 else "grazer").split(",")
	var size := float(args[1]) if args.size() > 1 else 64.0
	var days := int(args[2]) if args.size() > 2 else 30
	var count := float(args[3]) if args.size() > 3 else 20.0
	var dt := float(args[4]) if args.size() > 4 else 3600.0
	var every := int(args[5]) if args.size() > 5 else 2
	var w := TestWorlds.flat(16.0, 0.38, size, 9)
	var climate := TestWorlds.climate_for(w, 0.05)
	var plants := EcoDefaults.plants([&"grass", &"shrub"] if args.size() > 6 and args[6] == "grass" else [])
	var eco := EcoGrid.new()
	eco.setup(w, plants, climate)
	var pop := PopulationManager.new()
	pop.setup(w, eco, climate, 3, Genetics.settings_with_defaults())
	pop.migration_enabled = false
	var id := 1
	for p in presets:
		pop.seed_species(id, BodyPlanPresets.create(StringName(p)), count * (0.15 if p == "predator" else 1.0))
		id += 1
	var t0 := Time.get_ticks_msec()
	for day in days + 1:
		if day % every == 0:
			var line := "d%3d" % day
			for sid in range(1, id):
				var tot := 0.0
				var e := 0.0
				var inc := 0.0
				var dem := 0.0
				var mus := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
				var b := 0.0
				for pl in pop.pools_of(sid):
					tot += pl.count
					for s in pl.samples:
						var wt := s.weight * pl.count
						e += s.energy * wt
						inc += s.last_income * wt
						dem += s.last_demand * wt
						mus[0] += s.mu_starve * wt
						mus[1] += s.mu_thermal * wt
						mus[2] += s.mu_habitat * wt
						mus[3] += s.mu_water * wt
						mus[4] += s.mu_disease * wt
						mus[5] += s.mu_predation * wt
						b += s.fecundity * wt
				var n := maxf(tot, 1e-9)
				line += " | %d n=%6.1f e=%.2f inc/dem=%4.0f/%4.0f mu[st %.2f th %.2f hb %.2f wa %.2f di %.2f pr %.2f] b%.2f" % [sid, tot, e / n, inc / n, dem / n, mus[0] / n * DAY, mus[1] / n * DAY, mus[2] / n * DAY, mus[3] / n * DAY, mus[4] / n * DAY, mus[5] / n * DAY, b / n * DAY]
			line += " | grass %.0f carc %.0f" % [eco.total_biomass(0) / 1000.0, eco.carcasses.total_kg()]
			print(line)
		if day == days:
			break
		for k in maxi(1, int(DAY / dt)):
			TestWorlds.advance(climate, dt)
			eco.step_all(dt)
			pop.step(dt)
	print("%.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)
