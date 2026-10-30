extends SceneTree
func _initialize() -> void:
	await process_frame
	var sim := ArenaSim.new(true, 5)
	get_root().add_child(sim)
	sim.clear_plants()
	var pred := sim.spawn_preset(&"predator", Vector3(-20, 0, -10), &"adult", 0.3)
	var prey := sim.spawn_preset(&"turtle", Vector3(-8, 0, -10), &"adult", 0.9)
	pred.individual.heading = -PI * 0.5
	var t := 0.0
	var last := ""
	var lastp := ""
	while t < 120.0:
		sim.step(1.0 / 30.0)
		t += 1.0 / 30.0
		var a1: String = pred.get_status()["action"] if pred.is_alive() else "dead"
		var a2: String = prey.get_status()["action"] if prey.is_alive() else "dead"
		if a1 != last or a2 != lastp or int(t * 30) % 300 == 0:
			last = a1
			lastp = a2
			print("t=%.1f pred=%s (%.1f,%.1f) v=%.2f fat=%.2f | prey=%s (%.1f,%.1f) v=%.2f fear=%.2f hp=%.2f dist=%.1f" % [t, a1, pred.position.x, pred.position.z, pred.mover.speed, pred.muscles.mean_fatigue(), a2, prey.position.x, prey.position.z, prey.mover.speed, prey.brain.needs.fear, prey.individual.health, pred.position.distance_to(prey.position)])
		if not prey.is_alive() and sim.deaths.size() > 0 and t > 100:
			break
	print("deaths: ", sim.deaths)
	print("carcasses: ", sim.eco.carcasses.count(), " pred E=", pred.individual.energy_fraction(), " stomach=", pred.individual.stomach_total())
	quit()
