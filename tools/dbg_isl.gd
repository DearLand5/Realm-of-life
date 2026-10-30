extends SceneTree
const DAY := Units.SECONDS_PER_DAY
func _initialize() -> void:
	await process_frame
	var w := TestWorlds.islands(16.0, 128.0, 17)
	var climate := TestWorlds.climate_for(w, 0.05)
	climate.sandbox_resource_mult = 4.0
	var eco := EcoGrid.new()
	eco.setup(w, EcoDefaults.plants([&"grass", &"shrub"]), climate)
	var pop := PopulationManager.new()
	pop.setup(w, eco, climate, 5, Genetics.settings_with_defaults())
	pop.seed_species(1, BodyPlanPresets.create(&"grazer"), 12.0)
	for sec in pop.sectors:
		print("sector ", sec.index, " land ", snappedf(sec.land_frac, 0.01), " fresh ", sec.fresh_water, " pool ", sec.pools.has(1))
	for d in 21:
		if d % 4 == 0:
			for p in pop.pools_of(1):
				var r := p.rates
				print("d%d sec %d n=%.2f e=%.2f births %.3f deaths %s growth %.3f bmr %.0f inc %.0f" % [d, p.sector, p.count, p.mean_energy(), r.births, str(r.deaths).replace("\n", ""), r.growth_rate, r.bmr_w, r.income_total()])
		TestWorlds.advance(climate, DAY)
		eco.step_all(DAY)
		pop.step(DAY)
	quit(0)
