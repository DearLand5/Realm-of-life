extends SceneTree
const DAY := Units.SECONDS_PER_DAY
func _initialize() -> void:
	await process_frame
	var temp := float(OS.get_cmdline_user_args()[0])
	var w := TestWorlds.flat(temp, 0.5, 32.0, 9)
	var climate := TestWorlds.climate_for(w, 0.05)
	climate.sandbox_resource_mult = float(OS.get_cmdline_user_args()[1])
	var plants := EcoDefaults.plants([&"grass"])
	plants.resize(1)
	plants[0].temp_opt = temp
	plants[0].temp_tol = 15.0
	var eco := EcoGrid.new()
	eco.setup(w, plants, climate)
	var pop := PopulationManager.new()
	pop.setup(w, eco, climate, 5, Genetics.settings_with_defaults({"rate": 0.0}))
	pop.migration_enabled = false
	var bare := BodyPlanPresets.create(&"grazer")
	bare.set_value(&"fur_length", 0.35)
	bare.set_value(&"fat_reserve", 0.35)
	var furry := BodyPlanPresets.create(&"grazer")
	furry.set_value(&"fur_length", 1.3)
	furry.set_value(&"fat_reserve", 1.3)
	pop.seed_genotypes(1, [bare, furry], float(OS.get_cmdline_user_args()[2]))
	for d in 41:
		if pop.pools_of(1).is_empty():
			print("extinct d", d)
			break
		if d % 5 == 0:
			var p: SpeciesPool = pop.pools_of(1)[0]
			var line := "d%d n=%.1f" % [d, p.count]
			for s in p.samples:
				line += " | fur %.2f w=%.2f e=%.2f inc %.0f dem %.0f bmr %.0f mass %.0f mu_th %.2f fit %.3f" % [s.genome.value(&"fur_length"), s.weight, s.energy, s.last_income, s.last_demand, s.pp.bmr_watts, s.mass, s.mu_thermal * DAY, s.fitness * DAY]
			print(line)
		TestWorlds.advance(climate, DAY)
		eco.step_all(DAY)
		pop.step(DAY)
	quit(0)
