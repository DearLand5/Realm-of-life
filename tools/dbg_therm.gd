extends SceneTree
func _initialize() -> void:
	await process_frame
	for preset in ["grazer", "predator"]:
		var g := BodyPlanPresets.create(StringName(preset))
		for lv in [0.3, 0.6, 1.0]:
			g.set_value(&"fur_length", lv)
			g.set_value(&"fat_reserve", lv)
			g.set_value(&"endothermy", 0.8)
			var pq := Phenotype.build(g).physiology
			for t in [-25, -15, -8, 0]:
				var rq := ThermalModel.Result.new()
				ThermalModel.steady(pq, float(t), false, 0.5, 1.5, pq.maintenance_rate(pq.body_temp_set) * 1.6, 1.0, rq)
				print("  fur/fat %.1f T=%d body %.1f cold %.2f extra %.0f (bmr %.0f)" % [lv, t, rq.body_temp, rq.cold_stress, rq.extra_w, pq.bmr_watts])
		var pp := Phenotype.build(g).physiology
		print(preset, " mass ", pp.mass, " bmr ", pp.bmr_watts, " maxthermo ", pp.max_thermogenesis_w, " ins ", pp.insulation, " fat ", pp.fat_fraction, " opt ", pp.thermal_optimum, " tol ", pp.thermal_tolerance, " endo ", pp.endothermy)
		for t in [-30, -20, -10, -4, 5, 15, 25, 35]:
			var r := ThermalModel.Result.new()
			ThermalModel.steady(pp, float(t), false, 0.5, 1.5, pp.maintenance_rate(pp.body_temp_set) * 1.6, 1.0, r)
			print("  T=%d body %.1f cold %.2f heat %.2f extra %.0f perf %.2f" % [t, r.body_temp, r.cold_stress, r.heat_stress, r.extra_w, r.performance])
		for tr in ["fur_length", "fat_reserve", "endothermy"]:
			print("  ", tr, " ", g.value(StringName(tr)), " norm ", g.norm(StringName(tr)))
	quit(0)
