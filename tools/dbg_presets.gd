extends SceneTree
func _initialize() -> void:
	await process_frame
	var plants := EcoDefaults.plants()
	for id in BodyPlanPresets.IDS:
		var g := BodyPlanPresets.create(id)
		var ph := Phenotype.build(g)
		var s := PoolSample.create(g, ph, plants)
		var pp := ph.physiology
		print("%-10s mass %7.3f land_ok %.2f water_ok %.2f life %5.1fd mat %4.1fd breed %.3f/d diet %s meat_eater %s speed %.2f" % [id, pp.mass, s.land_ok, s.water_ok, pp.lifespan / 86400.0, pp.maturity_age / 86400.0, s.breed_rate * 86400.0, pp.diet, s.meat_eater, s.speed])
	quit(0)
