extends SceneTree
const DAY := Units.SECONDS_PER_DAY
func _initialize() -> void:
	await process_frame
	var w := TestWorlds.flat(16.0, 0.5, 64.0, 9)
	var climate := TestWorlds.climate_for(w, 0.05)
	var eco := EcoGrid.new()
	eco.setup(w, EcoDefaults.plants([&"grass", &"shrub"]), climate)
	for d in 61:
		if d % 5 == 0:
			print("d%d grass %.0f shrub %.0f det %.2f nut %.3f seasonal %.1f" % [d, eco.total_biomass(0), eco.total_biomass(1), eco.detritus[5], eco.nutrients[5], climate.seasonal_offset()])
		TestWorlds.advance(climate, DAY)
		eco.step_all(DAY)
	quit(0)
